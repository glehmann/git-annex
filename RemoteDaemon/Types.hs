{- git-remote-daemon data types.
 -
 - Copyright 2014 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

{-# LANGUAGE TypeSynonymInstances, FlexibleInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module RemoteDaemon.Types where

import qualified Annex
import qualified Git.Types as Git
import qualified Utility.SimpleProtocol as Proto

import Control.Concurrent

-- A Transport for a particular git remote consumes some messages
-- from a Chan, and emits others to another Chan.
type Transport = Git.Repo -> RemoteName -> Annex.AnnexState -> Chan Consumed -> Chan Emitted -> IO ()

-- Messages that the daemon emits.
data Emitted
	= CONNECTED RemoteName
	| DISCONNECTED RemoteName
	| SYNCING RemoteName
	| DONESYNCING RemoteName Bool

-- Messages that the deamon consumes.
data Consumed
	= PAUSE
	| RESUME
	| CHANGED RefList
	| RELOAD
	| STOP

type RemoteName = String
type RefList = [Git.Ref]

instance Proto.Sendable Emitted where
	formatMessage (CONNECTED remote) =
		["CONNECTED", Proto.serialize remote]
	formatMessage (DISCONNECTED remote) =
		["DISCONNECTED", Proto.serialize remote]
	formatMessage (SYNCING remote) =
		["SYNCING", Proto.serialize remote]
	formatMessage (DONESYNCING remote status) =
		["DONESYNCING", Proto.serialize remote, Proto.serialize status]

instance Proto.Sendable Consumed where
	formatMessage PAUSE = ["PAUSE"]
	formatMessage RESUME = ["RESUME"]
	formatMessage (CHANGED refs) =["CHANGED", Proto.serialize refs]
	formatMessage RELOAD = ["RELOAD"]
	formatMessage STOP = ["STOP"]

instance Proto.Receivable Emitted where
	parseCommand "CONNECTED" = Proto.parse1 CONNECTED
	parseCommand "DISCONNECTED" = Proto.parse1 DISCONNECTED
	parseCommand "SYNCING" = Proto.parse1 SYNCING
	parseCommand "DONESYNCING" = Proto.parse2 DONESYNCING
	parseCommand _ = Proto.parseFail

instance Proto.Receivable Consumed where
	parseCommand "PAUSE" = Proto.parse0 PAUSE
	parseCommand "RESUME" = Proto.parse0 RESUME
	parseCommand "CHANGED" = Proto.parse1 CHANGED
	parseCommand "RELOAD" = Proto.parse0 RELOAD
	parseCommand "STOP" = Proto.parse0 STOP
	parseCommand _ = Proto.parseFail

instance Proto.Serializable [Char] where
	serialize = id
	deserialize = Just

instance Proto.Serializable RefList where
	serialize = unwords . map Git.fromRef
	deserialize = Just . map Git.Ref . words

instance Proto.Serializable Bool where
	serialize False = "0"
	serialize True = "1"

	deserialize "0" = Just False
	deserialize "1" = Just True
	deserialize _ = Nothing
