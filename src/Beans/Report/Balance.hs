module Beans.Report.Balance where

import           Beans.Accounts           (Accounts, Key (..))
import           Beans.AST                (AccountName (..), Lot (NoLot))
import           Beans.Report.Table       (ColDesc (..), left, right, showTable)
import qualified Data.Map.Strict.Extended as M
import           Data.Scientific.Extended (FPFormat (Fixed), Scientific,
                                           formatScientific)
import           Data.Text.Lazy           (Text, pack)


printAccounts :: Accounts -> IO ()
printAccounts accounts =
  putStrLn $
  showTable
    [ ColDesc left "Account" left (show . keyAccount . fst)
    , ColDesc left "Amount" right (format . snd)
    , ColDesc left "Commodity" left (show . keyCommodity . fst)
    , ColDesc left "Lot" left (show . keyLot . fst)
    ]
    items
    totals
  where
    format = formatStandard
    items = M.toList accounts
    totals = M.toList . eraseLots . eraseAccounts "Total" $ accounts

formatStandard :: Scientific -> String
formatStandard = formatScientific Fixed (Just 2)

-- formatK :: Scientific -> String
-- formatK n = formatScientific Fixed (Just 0) (n `sdiv` 1000) ++ "k"

summarize :: Int -> Accounts -> Accounts
summarize d = M.mapKeysWith (+) m
  where
    m Key {..} = Key {keyAccount = AccountName $ take d (_unAccountName keyAccount), ..}

eraseLots :: Accounts -> Accounts
eraseLots = M.mapKeysWith (+) (\k -> k {keyLot = NoLot})

eraseAccounts :: Text -> Accounts -> Accounts
eraseAccounts label = M.mapKeysWith (+) m
  where
    m k = k { keyAccount = AccountName [label, pack $ show (keyCommodity k)] }
