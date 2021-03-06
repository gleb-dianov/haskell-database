module Engine.Functions.Table
( module Engine.Types.Table
, module Engine.Types.DB
, polyRead
, select
, getTableTypes
, where_
, toPath
, from
, readTable
, PrimaryKeyValues(..)
, getPKValues
, searchTable
, search
, to
, insert
) where


import           Control.Applicative
import           Control.Monad
import           Control.Monad.Trans
import           Control.Monad.Trans.Except
import           Control.Monad.Trans.Maybe
import           Data.Binary
import qualified Data.ByteString            as BS
import qualified Data.ByteString.Lazy       as BL
import           Data.List                  (elemIndex)
import           Data.Maybe                 (maybeToList)
import           Safe
import           System.IO

import           Common.Exception
import           Common.Maybe
import           Engine.Types.DB
import           Engine.Types.Table

thisModule :: String
thisModule = "Engine.Functions.Table"

toPath :: DBName -> TableName -> FilePath
toPath db = (("./.databases/" ++ db ++ "/") ++) . (++ ".table")

polyRead :: AType -> String -> PolyType
polyRead atype =
    case atype of
        BoolType    -> construct PolyBool
        IntType     -> construct PolyInt
        FloatType   -> construct PolyFloat
        StringType  -> construct PolyString
        InvalidType -> const Invalid
    where construct constructor = maybe Invalid constructor . readMay

select :: [String] -> Table -> Maybe Table
select names (Table types pKeys values) =
    toMaybe (length functionsList == length names)
    $ Table (getElems types) (filter (flip elem names) pKeys) (map (Row . getElems . unRow) values)
    where functionsList = join $ map (maybeToList . flip elemIndex (map fst types)) names
          getElems list = foldl (\p f -> p ++ [f list]) [] $ map (flip (!!)) functionsList

where_ :: ([(String, AType)] -> Row -> Bool) -> Table -> Table
where_ f (Table types pKeys values) = Table types pKeys $ filter (f types) values

from :: DBName -> [TableName] -> ExceptT Message IO Table
from db tables = ((tableProduct . zip tables) <$> mapM (readTable db) tables)
                 `catchT` (throwE . exceptionHandler thisModule "from")

readTable :: DBName -> TableName -> ExceptT Message IO Table
readTable db table = (lift $ fmap decodeTable $ BL.readFile $ toPath db table)
                     `catchT` (throwE . exceptionHandler thisModule "readTable")

getTableTypes :: DBName -> TableName -> ExceptT Message IO [(String, AType)]
getTableTypes db table = (fmap tableTypes $ from db [table])
                         `catchT` (throwE . exceptionHandler thisModule "getTableTypes")


newtype PrimaryKeyValues = PrimaryKeyValues { unPKV :: [PolyType] } deriving (Eq, Show)

getPKValues :: Table -> [(Row, PrimaryKeyValues)]
getPKValues table = zip (tableRows table)
                  $ fmap (PrimaryKeyValues . unRow)
                  $ maybe [] tableRows
                  $ select (primaryKeys table) table

searchTable :: PrimaryKeyValues -> Table -> Maybe Row
searchTable pkValues table = fmap fst $ headMay $ filter ((== pkValues) . snd) $ getPKValues table

search :: DBName -> TableName -> Row -> ExceptT Message (MaybeT IO) Row
search = undefined
-- search db table row = (lift $ MaybeT $ primKeysSearchTable row . decodeTable <$> (BL.readFile $ toPath db table)) `catchT` (throwE . exceptionHandler thisModule "search")

to :: DBName -> TableName -> Row -> ExceptT Message IO ()
to db table newData =
    if filter (== Invalid) (unRow newData) == []
       then (lift $ BL.appendFile (toPath db table) (BL.concat $ map encode $ unRow newData))
            `catchT` (throwE . exceptionHandler thisModule "to")
       else throwE "Cannot add invalid data!"

insert :: DBName -> TableName -> [String] -> ExceptT Message IO ()
insert db tableName strs = do
    table <- readTable db tableName
    let types = tableTypes table
        primaryKeyValues = fmap snd $ getPKValues $ table
        newRow = seq types $ Row $ zipWith polyRead (fmap snd types) strs
        newRowPKV = snd (head $ getPKValues $ Table types (primaryKeys table) [newRow])
    if (newRowPKV `elem` seq (length primaryKeyValues) primaryKeyValues)
       then throwE "Primary key is not unique!"
       else to db tableName newRow
