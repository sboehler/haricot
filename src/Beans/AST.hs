module Beans.AST
  ( module Beans.AST
  ) where

import qualified Data.List           as L
import           Data.Maybe          (catMaybes)
import           Data.Scientific     (Scientific)
import           Data.Text.Lazy      (Text, unpack)
import           Data.Time.Calendar  (Day)
import qualified Text.Megaparsec.Pos as P

data Directive
  = Bal Balance
  | Opn Open
  | Cls Close
  | Trn Transaction
  | Prc Price
  | Opt Option
  | Inc Include
  deriving (Show)

data Balance = Balance
  { _pos       :: Maybe P.SourcePos
  , _date      :: Day
  , _account   :: AccountName
  , _amount    :: Scientific
  , _commodity :: CommodityName
  } deriving (Show)

data Open = Open
  { _pos         :: Maybe P.SourcePos
  , _date        :: Day
  , _account     :: AccountName
  , _restriction :: Restriction
  } deriving (Show)

data Restriction
  = NoRestriction
  | RestrictedTo [CommodityName]
  deriving (Show)

instance Monoid Restriction where
  mempty = RestrictedTo []
  RestrictedTo x `mappend` RestrictedTo y = RestrictedTo (x `L.union` y)
  _ `mappend` _ = NoRestriction

compatibleWith :: CommodityName -> Restriction -> Bool
compatibleWith _ NoRestriction    = True
compatibleWith c (RestrictedTo r) = c `elem` r

data Close = Close
  { _pos     :: Maybe P.SourcePos
  , _date    :: Day
  , _account :: AccountName
  } deriving (Show)

data Price = Price
  { _pos             :: P.SourcePos
  , _date            :: Day
  , _commodity       :: CommodityName
  , _price           :: Scientific
  , _targetCommodity :: CommodityName
  } deriving (Show)

data Transaction = Transaction
  { _pos         :: Maybe P.SourcePos
  , _date        :: Day
  , _flag        :: Flag
  , _description :: Text
  , _tags        :: [Tag]
  , _postings    :: [Posting]
  } deriving (Show)

data Posting = Posting
  { _pos       :: Maybe P.SourcePos
  , _account   :: AccountName
  , _amount    :: Scientific
  , _commodity :: CommodityName
  , _lot       :: Maybe Lot
  } deriving (Show)

data Flag
  = Complete
  | Incomplete
  deriving (Show)

newtype Tag =
  Tag Text
  deriving (Show)

data Lot
  = Lot { _price           :: Scientific
        , _targetCommodity :: CommodityName
        , _date            :: Day
        , _label           :: Maybe Text }
  deriving (Eq, Ord)

instance Show Lot where
  show (Lot p t d l) =
    let price = show p ++ " " ++ show t
        elems = catMaybes [Just price, Just $ show d, show <$> l]
     in "{ " ++ L.intercalate ", " elems ++ " }"

data Include = Include
  {
    _pos      :: P.SourcePos,
    _filePath :: FilePath
  } deriving (Show)

data Option =
  Option P.SourcePos
         Text
         Text
  deriving (Show)

data AccountType
  = Assets
  | Liabilities
  | Equity
  | Income
  | Expenses
  deriving (Eq, Ord, Read, Show)

data AccountName = AccountName
  { _unAccountType :: AccountType
  , _unAccountName :: [Text]
  } deriving (Eq, Ord)

instance Show AccountName where
  show (AccountName t n) = L.intercalate ":" (show t : (unpack <$> n))

newtype CommodityName = CommodityName
  { _unCommodityName :: Text
  } deriving (Eq, Ord)

instance Show CommodityName where
  show (CommodityName n) = unpack n