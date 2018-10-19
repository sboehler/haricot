module Beans.Lib
  ( run
  , Command(..)
  )
where

import           Beans.Report                             ( balance
                                                          , journal
                                                          )
import           Beans.Import                             ( importCommand )
import           Beans.Options                            ( Command(..) )
import           Control.Monad.Catch                      ( MonadThrow )
import           Control.Monad.IO.Class                   ( MonadIO )

run :: (MonadIO m, MonadThrow m) => Command -> m ()
run command = case command of
  Balance options -> balance options
  Import  options -> importCommand options
  Journal options -> journal options
