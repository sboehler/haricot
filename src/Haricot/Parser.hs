module Haricot.Parser where

import           Control.Monad              (void)
import           Control.Monad.Catch        (MonadThrow, throwM)
import           Control.Monad.IO.Class     (MonadIO)
import           Control.Monad.Trans        (liftIO)
import           Data.Char                  (isAlphaNum)
import           Data.Functor               (($>))
import           Data.Scientific            (Scientific)
import           Data.Text.Lazy             (Text, cons, unpack)
import           Data.Text.Lazy.IO          (readFile)
import           Data.Time.Calendar         (Day, fromGregorian)
import           Data.Void                  (Void)
import           Haricot.AST
import           Prelude                    hiding (readFile)
import           System.FilePath.Posix      (combine, takeDirectory)
import           Text.Megaparsec
import           Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L
import qualified Text.Megaparsec.Pos        as P

type Parser = Parsec Void Text

lineComment :: Parser ()
lineComment =
  L.skipLineComment "*" <|> L.skipLineComment "#" <|> L.skipLineComment ";"

scn :: Parser ()
scn = L.space space1 lineComment empty

sc :: Parser ()
sc = L.space (void $ takeWhile1P Nothing f) empty empty
  where
    f x = x == ' ' || x == '\t'

lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc

symbol :: Text -> Parser Text
symbol = L.symbol sc

date :: Parser Day
date =
  lexeme $ fromGregorian <$> digits 4 <* dash <*> digits 2 <* dash <*> digits 2
  where
    dash = symbol "-"
    digits n = read <$> count n digitChar

account :: Parser AccountName
account = lexeme $ AccountName <$> segment `sepBy` colon
  where
    segment =
      cons <$> letterChar <*> takeWhileP (Just "alphanumeric") isAlphaNum
    colon = symbol ":"

commodity :: Parser CommodityName
commodity =
  lexeme $ CommodityName <$> takeWhileP (Just "alphanumeric") isAlphaNum

number :: Parser Scientific
number = lexeme $ L.signed sc L.scientific

braces :: Parser a -> Parser a
braces = between (symbol "{") (symbol "}")

quotedString :: Parser Text
quotedString =
  lexeme $ between quote quote (takeWhileP (Just "no quote") (/= '"'))
  where
    quote = char '"'

lot :: Day -> Parser Lot
lot d = braces $ Lot <$> number <*> commodity <*> lotDate <*> lotLabel
  where
    comma = symbol ","
    lotDate = (comma >> date) <|> pure d
    lotLabel = optional (comma >> quotedString)

postingPrice :: Parser ()
postingPrice = (symbol "@" *> optional (symbol "@") *> number *> commodity) $> ()

completePosting :: Day -> P.SourcePos -> AccountName -> Parser CompletePosting
completePosting d p a =
  CompletePosting p a <$> number <*> commodity <*> optional (lot d) <*
  optional postingPrice

wildcardPosting :: P.SourcePos -> AccountName -> Parser WildcardPosting
wildcardPosting p a = return $ WildcardPosting p a

posting :: Day -> Parser Posting
posting d = do
  pos <- getPosition
  a <- account
  CP <$> completePosting d pos a <|> WP <$> wildcardPosting pos a

flag :: Parser Flag
flag = complete <|> incomplete
  where
    complete = Complete <$ symbol "*"
    incomplete = Incomplete <$ symbol "!"

tag :: Parser Tag
tag = Tag <$> (cons <$> char '#' <*> takeWhile1P (Just "alphanum") isAlphaNum)

transaction :: P.SourcePos -> Day -> Parser (Transaction [Posting])
transaction pos d = do
  f <- flag
  desc <- quotedString
  t <- many tag
  indent <- L.indentGuard scn GT P.pos1
  p <- some $ try (L.indentGuard scn EQ indent *> posting d)
  return $ Transaction pos d f desc t p

open :: P.SourcePos -> Day -> Parser Open
open pos d = Open pos d <$ symbol "open" <*> account <*> restriction

restriction :: Parser Restriction
restriction =  RestrictedTo <$> (commodity `sepBy1` symbol ",") <|> return NoRestriction

close :: P.SourcePos -> Day -> Parser Close
close pos d = Close pos d <$ symbol "close" <*> account

balance :: P.SourcePos -> Day -> Parser Balance
balance pos d =
  Balance pos d <$ symbol "balance" <*> account <*> number <*> commodity

price :: P.SourcePos -> Day -> Parser Price
price pos d =
  Price pos d <$ symbol "price" <*> commodity <*> number <*> commodity

event :: Parser (Directive [Posting])
event = do
  pos <- getPosition
  d <- date
  Trn <$> transaction pos d <|> Opn <$> open pos d <|> Cls <$> close pos d <|>
    Bal <$> balance pos d <|>
    Prc <$> price pos d

include :: Parser Include
include = symbol "include" >> Include <$> getPosition <*> (unpack <$> quotedString)

config :: Parser Option
config = symbol "option" >> Option <$> getPosition <*> quotedString <*> quotedString

directive :: Parser (Directive [Posting])
directive =
  L.nonIndented scn $
  (event <|> Inc <$> include <|> Opt <$> config) <* scn

directives :: Parser [Directive [Posting]]
directives = some directive <* eof

parseSource :: (MonadThrow m) => FilePath -> Text -> m [Directive [Posting]]
parseSource f t =
  case parse directives f t of
    Left e  -> throwM e
    Right d -> return d

getIncludedFiles :: FilePath -> [Directive [Posting]] -> [FilePath]
getIncludedFiles fp ast =
  [combine (takeDirectory fp) path | (Inc (Include _ path)) <- ast]

parseFile :: (MonadIO m, MonadThrow m) => FilePath -> m [Directive [Posting]]
parseFile filePath = do
  source <- liftIO $ readFile filePath
  ast <- parseSource filePath source
  asts <- concat <$> traverse parseFile (getIncludedFiles filePath ast)
  return $ ast ++ asts
