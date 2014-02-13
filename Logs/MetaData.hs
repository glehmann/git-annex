{- git-annex general metadata storage log
 -
 - A line of the log will look like "timestamp field [+-]value [...]"
 -
 - Note that unset values are preserved. Consider this case:
 -
 - We have:
 -
 - 100 foo +x
 - 200 foo -x
 -
 - An unmerged remote has:
 -
 - 150 foo +x
 - 
 - After union merge, because the foo -x was preserved, we know that
 - after the other remote redundantly set foo +x, it was unset,
 - and so foo currently has no value.
 -
 -
 - Copyright 2014 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

{-# OPTIONS_GHC -fno-warn-orphans #-}

module Logs.MetaData (
	getCurrentMetaData,
	getMetaData,
	setMetaData,
	unsetMetaData,
	addMetaData,
	currentMetaData,
) where

import Common.Annex
import Types.MetaData
import qualified Annex.Branch
import Logs
import Logs.SingleValue

import qualified Data.Set as S
import Data.Time.Clock.POSIX

instance SingleValueSerializable MetaData where
	serialize = Types.MetaData.serialize
	deserialize = Types.MetaData.deserialize

getMetaData :: Key -> Annex (Log MetaData)
getMetaData = readLog . metaDataLogFile

{- Go through the log from oldest to newest, and combine it all
 - into a single MetaData representing the current state. -}
getCurrentMetaData :: Key -> Annex MetaData
getCurrentMetaData = currentMetaData . collect <$$> getMetaData
  where
	collect = foldl' unionMetaData newMetaData . map value . S.toAscList

setMetaData :: Key -> MetaField -> String -> Annex ()
setMetaData = setMetaData' True

unsetMetaData :: Key -> MetaField -> String -> Annex ()
unsetMetaData = setMetaData' False

setMetaData' :: Bool -> Key -> MetaField -> String -> Annex ()
setMetaData' isset k field s = addMetaData k $
	updateMetaData field (mkMetaValue (CurrentlySet isset) s) newMetaData

{- Adds in some metadata, which can override existing values, or unset
 - them, but otherwise leaves any existing metadata as-is. -}
addMetaData :: Key -> MetaData -> Annex ()
addMetaData k metadata = do
        now <- liftIO getPOSIXTime
	Annex.Branch.change (metaDataLogFile k) $
		showLog . simplifyLog 
			. S.insert (LogEntry now metadata) 
			. parseLog

{- Simplify a log, removing historical values that are no longer
 - needed. 
 -
 - This is not as simple as just making a single log line with the newest
 - state of all metadata. Consider this case:
 -
 - We have:
 -
 - 100 foo +x bar +y
 - 200 foo -x
 -
 - An unmerged remote has:
 -
 - 150 bar +z baz +w
 -
 - If what we have were simplified to "200 foo -x bar +y" then when the line
 - from the remote became available, it would be older than the simplified
 - line, and its change to bar would not take effect. That is wrong.
 -
 - Instead, simplify it to:                   (this simpliciation is optional)
 -
 - 100 bar +y                                 (100 foo +x bar +y)
 - 200 foo -x
 -
 - Now merging with the remote yields:
 -
 - 100 bar +y                                 (100 foo +x bar +y)
 - 150 bar +z baz +w
 - 200 foo -x
 -
 - Simplifying again:
 -
 - 150 bar +z baz +w
 - 200 foo -x
 -
 - In practice, there is little benefit to making simplications to lines
 - that only remove some values, while leaving others on the line.
 - Since lines are kept in git, that likely increases the size of the
 - git repo (depending on compression), rather than saving any space.
 -
 - So, the only simplication that is actually done is to throw out an
 - old line when all the values in it have been overridden by lines that
 - came after.
 -}
simplifyLog :: Log MetaData -> Log MetaData
simplifyLog s = case S.toDescList s of
	(newest:rest) -> S.fromList $ go [newest] (value newest) rest
	_ -> s
  where
	go c _ [] = c
	go c newer (l:ls)
		| hasUniqueMetaData newer older =
			go (l:c) (unionMetaData older newer) ls
		| otherwise = go c newer ls
	  where
		older = value l
