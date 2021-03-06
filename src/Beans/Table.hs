module Beans.Table
  ( Cell (..),
    Table (..),
    Row (..),
    rowLength,
    display,
    emptyRow,
  )
where

import Data.Coerce (coerce)
import qualified Data.List as List
import Data.Map.Strict ((!))
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Prelude hiding (lines)

data Table = Table [Int] [Row] deriving (Show)

newtype Row = Row [Cell]
  deriving (Show, Semigroup, Monoid)

data Cell
  = AlignLeft Text
  | AlignRight Text
  | AlignCenter Text
  | Separator
  | IndentBy Int Text
  | Empty
  deriving (Show)

emptyRow :: Row
emptyRow = Row [Empty]

rowLength :: Row -> Int
rowLength (Row l) = List.length l

display :: Table -> Text
display (Table colgroups rows) = Text.unlines $ render <$> rows
  where
    cellWidths = [[cellWidth cell | cell <- r] | Row r <- rows]
    columnWidths = [maximum col | col <- List.transpose cellWidths]
    groupWidths = Map.fromListWith max $ colgroups `zip` columnWidths
    cw = (groupWidths !) <$> colgroups
    render =
      pad "|"
        . List.foldl' combine mempty
        . zip cw
        . (<> repeat Empty)
        . coerce

cellWidth :: Cell -> Int
cellWidth Separator = 0
cellWidth Empty = 0
cellWidth (AlignLeft t) = Text.length t
cellWidth (AlignRight t) = Text.length t
cellWidth (AlignCenter t) = Text.length t
cellWidth (IndentBy n t) = n + Text.length t

combine :: Text -> (Int, Cell) -> Text
combine "" (n, c) = format n c
combine t (n, Separator) = t <> "+" <> format n Separator
combine t (n, c) = t <> "|" <> format n c

format :: Int -> Cell -> Text
format n Separator = pad dash $ Text.replicate n dash
format n (AlignLeft t) = pad space $ Text.justifyLeft n spaceChar t
format n (AlignRight t) = pad space $ Text.justifyRight n spaceChar t
format n (AlignCenter t) = pad space $ Text.center n spaceChar t
format n Empty = pad space $ Text.replicate n space
format n (IndentBy i t) = pad space (indent <> Text.justifyLeft (n - i) spaceChar t)
  where
    indent = Text.replicate i space

pad :: Text -> Text -> Text
pad padding content = padding <> content <> padding

spaceChar :: Char
spaceChar = ' '

space :: Text
space = " "

dash :: Text
dash = "-"
