module Main where

import           Beans.Lib           (Command (..), Options (..), runBeans)
import           Data.Semigroup      ((<>))
import           Options.Applicative

import           Beans.Data.Accounts (CommodityName)
import qualified Beans.Parser        as P
import qualified Data.Text           as T
import           Data.Time.Calendar  (Day)
import           Text.Megaparsec     (parseMaybe)


toReadM :: P.Parser a -> ReadM a
toReadM p = maybeReader $ parseMaybe p . T.pack

market :: Parser (Maybe CommodityName)
market =
  optional $ option (toReadM P.commodity) (long "at-value" <> short 'v')

lots :: Parser Bool
lots =
  switch (long "lots" <> short 'l')

dateparser :: String -> Parser (Maybe Day)
dateparser l = optional $ option (toReadM P.date) (long l)

journal :: Parser FilePath
journal =
  option
    str
    (value "journal.bean" <> metavar "JOURNAL" <>
     help "The journal file to parse" <>
     long "journal" <>
     short 'j')

depth :: Parser (Maybe Int)
depth =
  optional $
  option
    auto
    (metavar "DEPTH" <> help "summarize accounts at level DEPTH" <> long "depth" <>
     short 'd')

cmd :: Parser Command
cmd =
  subparser $
  command "balance" (info (pure Balance) (progDesc "Print a balance sheet"))

config :: Parser Options
config =
  Options <$> journal <*> market <*> lots <*> dateparser "from" <*>
  dateparser "to" <*> depth <*>
  cmd

parserConfig :: ParserInfo Options
parserConfig =
  info
    (helper <*> config)
    (fullDesc <> progDesc "Evaluate a journal" <>
     header "Beans - a plain text accounting tool")

main :: IO ()
main = execParser parserConfig >>= runBeans
