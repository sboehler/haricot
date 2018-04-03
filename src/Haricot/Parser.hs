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

posting :: Day -> Parser Posting
posting d = do
  pos <- getPosition
  a <- account
  Posting pos a <$> number <*> commodity <*> optional (lot d) <*
    optional postingPrice <|> return (Wildcard pos a)

flag :: Parser Flag
flag = complete <|> incomplete
  where
    complete = Complete <$ symbol "*"
    incomplete = Incomplete <$ symbol "!"

tag :: Parser Tag
tag = Tag <$> (cons <$> char '#' <*> takeWhile1P (Just "alphanum") isAlphaNum)

transaction :: P.SourcePos -> Day -> Parser Event
transaction pos d = do
  f <- flag
  desc <- quotedString
  t <- many tag
  indent <- L.indentGuard scn GT P.pos1
  p <- some $ try (L.indentGuard scn EQ indent *> posting d)
  return $ Trn $ Transaction pos d f desc t p

open :: P.SourcePos -> Day -> Parser Event
open pos d = Opn <$> (Open pos d <$ symbol "open" <*> account <*> (commodity `sepBy` symbol ","))

close :: P.SourcePos -> Day -> Parser Event
close pos d = Cls <$> (Close pos d <$ symbol "close" <*> account)

balance :: P.SourcePos -> Day -> Parser Event
balance pos d =
  Bal <$> (Balance pos d <$ symbol "balance" <*> account <*> number <*> commodity)

price :: P.SourcePos -> Day -> Parser Event
price pos d =
  Prc <$> (Price pos d <$ symbol "price" <*> commodity <*> number <*> commodity)

event :: Parser Event
event = do
  pos <- getPosition
  d <- date
  transaction pos d <|> open pos d <|> close pos d <|> balance pos d <|>
    price pos d

include :: Parser Include
include = symbol "include" >> Include <$> getPosition <*> (unpack <$> quotedString)

config :: Parser Option
config = symbol "option" >> Option <$> getPosition <*> quotedString <*> quotedString

directive :: Parser Directive
directive =
  L.nonIndented scn $
  (Evt <$> event <|> Inc <$> include <|> Opt <$> config) <* scn

directives :: Parser [Directive]
directives = some directive <* eof

parseSource :: (MonadThrow m) => FilePath -> Text -> m [Directive]
parseSource f t =
  case parse directives f t of
    Left e  -> throwM e
    Right d -> return d

getIncludedFiles :: FilePath -> [Directive] -> [FilePath]
getIncludedFiles fp ast =
  [combine (takeDirectory fp) path | (Inc (Include _ path)) <- ast]

parseFile ::
     (MonadIO m, MonadThrow m) => FilePath -> m [Directive]
parseFile filePath = do
  source <- liftIO $ readFile filePath
  ast <- parseSource filePath source
  asts <- traverse parseFile (getIncludedFiles filePath ast)
  return $ ast ++ concat asts
