module Beans.Report.Balance
  ( Report(..)
  , reportToTable
  , incomeStatement
  , balanceSheet
  , createReport
  , incomeStatementToTable
  , balanceSheetToTable
  )
where

import           Beans.Data.Accounts                      ( Accounts
                                                          , Account(..)
                                                          , Amount
                                                          , Amounts
                                                          , AccountType(..)
                                                          , Commodity(..)
                                                          , format
                                                          , Lot(..)
                                                          , Position(..)
                                                          , eraseLots
                                                          , summarize
                                                          )
import           Beans.Accounts                           ( calculateAccountsForDays
                                                          )
import           Beans.Ledger                             ( Ledger )
import           Data.Group                               ( invert )
import qualified Beans.Data.Map                as M
import           Beans.Pretty                             ( pretty )
import           Beans.Table                              ( Cell(..) )
import           Beans.Options                            ( BalanceOptions(..)
                                                          , ReportType(..)
                                                          )
import           Data.Foldable                            ( fold )
import           Data.Monoid                              ( (<>) )
import           Data.Text                                ( Text )
import qualified Data.List                     as List
import qualified Beans.Ledger                  as L
import qualified Data.Text                     as T
import           Control.Monad.Catch                      ( MonadThrow )


type Positions = M.Map (Commodity, Maybe Lot) Amounts

data Report = Report
  { sPositions :: Positions
  , sReports  :: M.Map Text Report
  , sSubtotals :: Positions
  } deriving (Show)

data IncomeStatement = IncomeStatement
  { sIncome :: Report,
    sExpenses :: Report,
    sTotal :: Positions
   } deriving(Show)

data BalanceSheet = BalanceSheet
  { bAssets :: Report,
    bLiabilities :: Report,
    bEquity :: Report
   } deriving(Show)


-- Creating a report
createReport :: MonadThrow m => BalanceOptions -> Ledger -> m Report
createReport BalanceOptions {..} ledger = do
  [a0, a1] <- calculateAccountsForDays (L.filter balOptFilter ledger)
                                       [balOptFrom, balOptTo]
                                       mempty
  let balance =
        eraseLots balOptLots
          . summarize balOptDepth
          . M.filter (not . null)
          . fmap (M.filter (/= 0))
          $ (a1 `M.minus` a0)
  return $ accountsToReport balOptReportType balance


-- Creating a report
incomeStatement :: MonadThrow m => BalanceOptions -> Ledger -> m IncomeStatement
incomeStatement BalanceOptions {..} ledger = do
  let filtered = L.filter balOptFilter ledger
  [a0, a1] <- calculateAccountsForDays filtered [balOptFrom, balOptTo] mempty
  let balance =
        eraseLots balOptLots
          . summarize balOptDepth
          . M.filter (not . null)
          . fmap (M.filter (/= 0))
          $ (a0 `M.minus` a1)
      income = M.filterKeys ((`elem` [Income]) . aType . pAccount) balance
      expenses = M.filterKeys ((`elem` [Expenses]) . aType . pAccount) balance
      incomeSection = accountsToReport balOptReportType income
      expensesSection = accountsToReport balOptReportType expenses
      is = IncomeStatement
        incomeSection { sSubtotals = mempty }
        expensesSection { sSubtotals = mempty }
        (sSubtotals incomeSection `mappend` sSubtotals expensesSection)
  return is

balanceSheet :: MonadThrow m => BalanceOptions -> Ledger -> m BalanceSheet
balanceSheet BalanceOptions {..} ledger = do
  let filtered = L.filter balOptFilter ledger
  [a0, a1] <- calculateAccountsForDays filtered [balOptFrom, balOptTo] mempty
  let
    balance =
      eraseLots balOptLots
        . summarize balOptDepth
        . M.filter (not . null)
        . fmap (M.filter (/= 0))
        $ (a1 `M.minus` a0)
    assets = M.filterKeys ((`elem` [Assets]) . aType . pAccount) balance
    liabilities =
      invert
        <$> M.filterKeys ((`elem` [Liabilities]) . aType . pAccount) balance
    equity =
      invert <$> M.filterKeys ((`elem` [Equity]) . aType . pAccount) balance
    retainedEarnings =
      invert
        <$> M.filterKeys ((`elem` [Income, Expenses]) . aType . pAccount)
                         balance
    retEarn = M.mapKeysM
      (\p -> p { pAccount = Account Equity ["RetainedEarnings"] })
      retainedEarnings

    assetsSection      = accountsToReport balOptReportType assets
    liabilitiesSection = accountsToReport balOptReportType liabilities
    equitySection      = accountsToReport balOptReportType (equity <> retEarn)
    is = BalanceSheet assetsSection liabilitiesSection equitySection
  return is


incomeStatementToTable :: IncomeStatement -> [[Cell]]
incomeStatementToTable IncomeStatement {..} =
  [Separator, Separator, Separator]
    :  [AlignLeft "Account", AlignLeft "Amount", AlignLeft "Commodity"]
    :  [Separator, Separator, Separator]
    :  sectionToRows 0 ("", sIncome)
    ++ [Separator, Separator, Separator]
    :  sectionToRows 0 ("", sExpenses)
    ++ [[Separator, Separator, Separator]]
    ++ sectionToRows 0 ("Total", Report sTotal M.empty sTotal)
    ++ [[Separator, Separator, Separator]]

balanceSheetToTable :: BalanceSheet -> [[Cell]]
balanceSheetToTable BalanceSheet {..}
  = let
      header    = AlignLeft <$> ["Account", "Amount", "Commodity"]
      sep       = replicate 3 Separator
      header'   = sep : header : pure sep
      filler    = repeat $ replicate 3 Empty
      emptyLine = pure $ replicate 3 Empty
      aSide = header' ++ sectionToRows 0 ("", bAssets { sSubtotals = mempty })
      leSide =
        header'
          ++ sectionToRows 0 ("", bLiabilities { sSubtotals = mempty })
          ++ emptyLine
          ++ sectionToRows 0 ("", bEquity { sSubtotals = mempty })
      totalAssets =
        sectionToRows 0 ("Total", Report mempty M.empty (sSubtotals bAssets))
      totalLiabilitiesAndEquity = sectionToRows
        0
        ( "Total"
        , Report mempty M.empty (sSubtotals bLiabilities <> sSubtotals bEquity)
        )
      nbrRows = maximum [length aSide, length leSide]
      aSide'  = take nbrRows (aSide ++ filler) ++ [sep] ++ totalAssets
      leSide' = take nbrRows (leSide ++ filler) ++ [sep] ++ totalLiabilitiesAndEquity
    in
      zipWith (++) aSide' leSide' ++ [replicate 6 Separator]




accountsToReport :: ReportType -> Accounts -> Report
accountsToReport reportType = groupLabeledPositions . M.mapEntries f
 where
  f (k@Position { pCommodity, pLot }, amount) =
    (labelFunction reportType k, M.singleton (pCommodity, pLot) amount)

labelFunction :: ReportType -> Position -> [Text]
labelFunction Hierarchical = T.splitOn ":" . T.pack . show . pAccount
labelFunction Flat =
  (\(Account t a) -> [T.pack $ show t, T.intercalate ":" a]) . pAccount

groupLabeledPositions :: M.Map [Text] Positions -> Report
groupLabeledPositions labeledPositions = Report positions
                                                subsections
                                                (positions <> subtotals)
 where
  positions = M.findWithDefaultM mempty labeledPositions
  subsections =
    groupLabeledPositions <$> splitReport (M.delete mempty labeledPositions)
  subtotals = fold (sSubtotals <$> subsections)

splitReport :: M.Map [Text] Positions -> M.Map Text (M.Map [Text] Positions)
splitReport = M.mapEntries f
 where
  f (n : ns, ps) = (n, M.singleton ns ps)
  f ([]    , ps) = (mempty, M.singleton [] ps)

-- Formatting a report into a table
reportToTable :: Report -> [[Cell]]
reportToTable t =
  [Separator, Separator, Separator]
    :  [AlignLeft "Account", AlignLeft "Amount", AlignLeft "Commodity"]
    :  [Separator, Separator, Separator]
    :  sectionToRows 0 ("", t)
    ++ [[Separator, Separator, Separator]]


sectionToRows :: Int -> (Text, Report) -> [[Cell]]
sectionToRows n (label, Report _ subsections subtotals) =
  positionRows ++ subsectionRows
 where
  subsectionRows = indent n <$> (sectionToRows 2 =<< M.toList subsections)
  positionRows   = positionsToRows label subtotals

positionsToRows :: Text -> Positions -> [[Cell]]
positionsToRows title subtotals =
  let
    positions = flattenPositions subtotals
    nbrRows   = maximum [if title == "" then 0 else 1, length positions]
    quantify  = take nbrRows . (++ repeat Empty)
    accounts  = [AlignLeft title]
    amounts   = AlignRight . format . (\(_, _, amount) -> amount) <$> positions
    commodities =
      AlignLeft
        .   T.pack
        .   unwords
        .   (\(lot, commodity, _) ->
              [show commodity, maybe "" (show . pretty) lot]
            )
        <$> positions
  in
    List.transpose [quantify accounts, quantify amounts, quantify commodities]

flattenPositions :: Positions -> [(Maybe Lot, Commodity, Amount)]
flattenPositions positions = do
  (lot      , amounts) <- (M.toList . M.mapKeysM snd) positions
  (commodity, amount ) <- M.toList amounts
  return (lot, commodity, amount)

indent :: Int -> [Cell] -> [Cell]
indent n (AlignLeft t   : ts) = IndentBy n t : ts
indent n (IndentBy n' t : ts) = IndentBy (n + n') t : ts
indent _ cs                   = cs
