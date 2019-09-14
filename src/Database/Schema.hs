{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE ImpredicativeTypes #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC  -fno-warn-missing-signatures #-}
module Database.Schema where

import Data.Aeson ((.=), ToJSON (..), object)
import Data.Time.LocalTime (LocalTime)
import Database.Beam
import Database.Beam.Backend.SQL.SQL92
import Database.Beam.Postgres (Postgres)
import RIO

--------------------------------------------------------------------------------
newtype Email = Email Text
  deriving (ToJSON, Show, Eq, FromBackendRow Postgres) via Text

deriving via Text instance HasSqlValueSyntax be Text => HasSqlValueSyntax be Email

--------------------------------------------------------------------------------
newtype HashedPassword = HashedPassword Text
  deriving (Show, Eq, FromBackendRow Postgres) via Text

deriving via Text instance HasSqlValueSyntax be Text => HasSqlValueSyntax be HashedPassword

--------------------------------------------------------------------------------
data UserT f
  = User
      { _userId :: Columnar f Int64
      , _userEmail :: Columnar f Email
      , _userHashedPassword :: Columnar f HashedPassword
      , _userCreatedAt :: Columnar f LocalTime
      }
  deriving Generic

instance Beamable UserT

instance Table UserT where

  data PrimaryKey UserT f = UserId (Columnar f Int64)
    deriving (Generic, Beamable)

  primaryKey = UserId . _userId

type User = UserT Identity

deriving instance Show User

deriving instance Eq User

instance ToJSON User where

  toJSON user = object ["id" .= (user ^. userId), "email" .= (user ^. email)]

type UserId = PrimaryKey UserT Identity

User
  (LensFor userId)
  (LensFor email)
  (LensFor hashedPassword)
  (LensFor createdAt) = tableLenses

--------------------------------------------------------------------------------
data BeansDb f
  = BeansDb
      {_beansUsers :: f (TableEntity UserT)}
  deriving (Generic, Database be)

beansDb :: DatabaseSettings be BeansDb
beansDb = defaultDbSettings
