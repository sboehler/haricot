module Haricot.Lib
  ( parse
  ) where

import           Control.Monad.Catch    (MonadThrow)
import           Control.Monad.IO.Class (MonadIO)
import           Control.Monad.Trans    (liftIO)
import qualified Data.Map.Strict        as M
import           Data.Time.Calendar     (fromGregorian)
import           Haricot.Accounts       (calculateAccounts)
import           Haricot.AST            (AccountName (..), CommodityName (..))
import           Haricot.Ledger         (buildLedger)
import           Haricot.Parser         (parseFile)
import           Haricot.Report.Balance (printAccounts, summarize)
import           Haricot.Valuation      (calculateValuation)
import           System.Environment     (getArgs)


parse :: (MonadIO m, MonadThrow m) => m ()
parse = do
  (file:_) <- liftIO getArgs
  ledger <- buildLedger <$> parseFile file
  let target = CommodityName "CHF"
      account = AccountName ["Equity", "Valuation"]
  valHistory <- calculateAccounts =<< calculateValuation target account ledger
  let accounts = M.lookupLE (fromGregorian 2017 12 9) valHistory
  case accounts of
    Just (_, a) -> liftIO $ printAccounts $ summarize 2 a
    Nothing     -> return ()
