{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE RecordWildCards #-}
{- HLINT ignore "Reduce duplication" -}

module Monomer.Widget.CompositeWidget (
  EventResponse(..),
  EventHandler,
  UIBuilder,
  composite
) where

import Control.Concurrent.STM.TChan
import Control.Monad.STM (atomically)
import Data.Default
import Data.List (foldl')
import Data.Map.Strict (Map)
import Data.Maybe
import Data.Sequence (Seq(..), (|>), (<|), fromList)
import Data.Typeable (Typeable, cast, typeOf)

import qualified Data.Map.Strict as M
import qualified Data.Sequence as Seq

import Monomer.Common.Geometry
import Monomer.Common.Tree
import Monomer.Event.Core
import Monomer.Event.Types
import Monomer.Graphics.Renderer
import Monomer.Widget.PathContext
import Monomer.Widget.Types
import Monomer.Widget.Util

type EventHandler s e ep = s -> e -> EventResponse s e ep
type UIBuilder s e = s -> WidgetInstance s e
type TaskHandler e = IO (Maybe e)
type ProducerHandler e = (e -> IO ()) -> IO ()

data EventResponse s e ep
  = Model s
  | Event e
  | Report ep
  | forall i . Typeable i => Message WidgetKey i
  | Task (TaskHandler e)
  | Producer (ProducerHandler e)
  | Multiple (Seq (EventResponse s e ep))

instance Semigroup (EventResponse s e ep) where
  Multiple seq1 <> Multiple seq2 = Multiple (seq1 <> seq2)
  Multiple seq1 <> er2 = Multiple (seq1 |> er2)
  er1 <> Multiple seq2 = Multiple (er1 <| seq2)
  er1 <> er2 = Multiple (Seq.singleton er1 |> er2)

data Composite s e ep = Composite {
  _widgetType :: WidgetType,
  _eventHandler :: EventHandler s e ep,
  _uiBuilder :: UIBuilder s e
}

data CompositeState s e = CompositeState {
  _compositeModel :: s,
  _compositeRoot :: WidgetInstance s e,
  _compositeInitEvent :: Maybe e,
  _compositeGlobalKeys :: GlobalKeys s e,
  _compositeSizeReq :: Tree SizeReq
}

data ReducedEvents s e sp ep = ReducedEvents {
  _reModel :: s,
  _reEvents :: Seq e,
  _reMessages :: Seq (WidgetRequest sp),
  _reReports :: Seq ep,
  _reTasks :: Seq (TaskHandler e),
  _reProducers :: Seq (ProducerHandler e)
}

composite :: (Eq s, Typeable s, Typeable e) => WidgetType -> s -> Maybe e -> EventHandler s e ep -> UIBuilder s e -> WidgetInstance sp ep
composite widgetType model initEvent eventHandler uiBuilder = defaultWidgetInstance widgetType widget where
  widgetRoot = uiBuilder model
  composite = Composite widgetType eventHandler uiBuilder
  state = CompositeState model widgetRoot initEvent M.empty (singleNode def)
  widget = createComposite composite state

createComposite :: (Eq s, Typeable s, Typeable e) => Composite s e ep -> CompositeState s e -> Widget sp ep
createComposite comp state = widget where
  widget = Widget {
    _widgetInit = compositeInit comp state,
    _widgetGetState = makeState state,
    _widgetMerge = compositeMerge comp state,
    _widgetNextFocusable = compositeNextFocusable state,
    _widgetFind = compositeFind state,
    _widgetHandleEvent = compositeHandleEvent comp state,
    _widgetHandleMessage = compositeHandleMessage comp state,
    _widgetPreferredSize = compositePreferredSize state,
    _widgetResize = compositeResize comp state,
    _widgetRender = compositeRender state
  }

compositeInit :: (Eq s, Typeable s, Typeable e) => Composite s e ep -> CompositeState s e -> WidgetEnv sp ep -> PathContext -> WidgetInstance sp ep -> WidgetResult sp ep
compositeInit comp state wenv ctx widgetComposite = result where
  CompositeState{..} = state
  widget = _instanceWidget _compositeRoot
  cwenv = convertWidgetEnv wenv _compositeGlobalKeys _compositeModel
  cctx = childContext ctx
  WidgetResult reqs evts root = _widgetInit widget cwenv cctx _compositeRoot
  newEvts = maybe evts (evts |>) _compositeInitEvent
  newState = state {
    _compositeGlobalKeys = collectGlobalKeys M.empty cctx _compositeRoot
  }
  result = processWidgetResult comp newState wenv ctx widgetComposite (WidgetResult reqs newEvts root)

compositeMerge :: (Eq s, Typeable s, Typeable e) => Composite s e ep -> CompositeState s e -> WidgetEnv sp ep -> PathContext -> WidgetInstance sp ep -> WidgetInstance sp ep -> WidgetResult sp ep
compositeMerge comp state wenv ctx oldComposite newComposite = result where
  oldState = _widgetGetState (_instanceWidget oldComposite) wenv
  validState = fromMaybe state (useState oldState)
  CompositeState oldModel oldRoot oldInit oldGlobalKeys oldReqs = validState
  -- Duplicate widget tree creation is avoided because the widgetRoot created on _composite_ has not yet been evaluated
  newRoot = _uiBuilder comp oldModel
  newState = validState {
    _compositeRoot = newRoot,
    _compositeGlobalKeys = collectGlobalKeys M.empty (childContext ctx) newRoot
  }
  newWidget = _instanceWidget newRoot
  cwenv = convertWidgetEnv wenv oldGlobalKeys oldModel
  cctx = childContext ctx
  widgetResult = if instanceMatches newRoot oldRoot
                  then _widgetMerge newWidget cwenv cctx oldRoot newRoot
                  else _widgetInit newWidget cwenv cctx newRoot
  result = processWidgetResult comp newState wenv ctx newComposite widgetResult

compositeNextFocusable :: CompositeState s e -> WidgetEnv sp ep -> PathContext -> WidgetInstance sp ep -> Maybe Path
compositeNextFocusable CompositeState{..} wenv ctx widgetComposite = _widgetNextFocusable widget cwenv cctx _compositeRoot where
  widget = _instanceWidget _compositeRoot
  cwenv = convertWidgetEnv wenv _compositeGlobalKeys _compositeModel
  cctx = childContext ctx

compositeFind :: CompositeState s e -> WidgetEnv sp ep -> Path -> Point -> WidgetInstance sp ep -> Maybe Path
compositeFind CompositeState{..} wenv path point widgetComposite
  | validStep = fmap (0 <|) childPath
  | otherwise = Nothing
  where
    widget = _instanceWidget _compositeRoot
    cwenv = convertWidgetEnv wenv _compositeGlobalKeys _compositeModel
    validStep = Seq.null path || Seq.index path 0 == 0
    newPath = Seq.drop 1 path
    childPath = _widgetFind widget cwenv newPath point _compositeRoot

compositeHandleEvent :: (Eq s, Typeable s, Typeable e) => Composite s e ep -> CompositeState s e -> WidgetEnv sp ep -> PathContext -> SystemEvent -> WidgetInstance sp ep -> Maybe (WidgetResult sp ep)
compositeHandleEvent comp state wenv ctx evt widgetComposite = fmap processEvent result where
  CompositeState{..} = state
  widget = _instanceWidget _compositeRoot
  cwenv = convertWidgetEnv wenv _compositeGlobalKeys _compositeModel
  cctx = childContext ctx
  processEvent = processWidgetResult comp state wenv ctx widgetComposite
  result = _widgetHandleEvent widget cwenv cctx evt _compositeRoot

processWidgetResult :: (Eq s, Typeable s, Typeable e) => Composite s e ep -> CompositeState s e -> WidgetEnv sp ep -> PathContext -> WidgetInstance sp ep -> WidgetResult s e -> WidgetResult sp ep
processWidgetResult comp state wenv ctx widgetComposite (WidgetResult reqs evts evtsRoot) = WidgetResult newReqs newEvts uWidget where
  CompositeState{..} = state
  evtUpdates = getUpdateUserStates reqs
  evtModel = foldr (.) id evtUpdates _compositeModel
  ReducedEvents newModel _ messages reports tasks producers = reduceCompositeEvents _compositeGlobalKeys (_eventHandler comp) evtModel evts
  WidgetResult uReqs uEvts uWidget = updateComposite comp state wenv ctx newModel evtsRoot widgetComposite
  newReqs = convertRequests reqs
         <> convertTasksToRequests ctx tasks
         <> convertProducersToRequests ctx producers
         <> convertRequests uReqs
         <> messages
  newEvts = reports <> uEvts

updateComposite :: (Eq s, Typeable s, Typeable e) => Composite s e ep -> CompositeState s e -> WidgetEnv sp ep -> PathContext -> s -> WidgetInstance s e -> WidgetInstance sp ep -> WidgetResult sp ep
updateComposite comp state wenv ctx newModel oldRoot widgetComposite = if modelChanged then processedResult else updatedResult where
  CompositeState{..} = state
  widget = _instanceWidget _compositeRoot
  cwenv = convertWidgetEnv wenv _compositeGlobalKeys newModel
  cctx = childContext ctx
  modelChanged = _compositeModel /= newModel
  builtRoot = _uiBuilder comp newModel
  mergedResult = _widgetMerge (_instanceWidget builtRoot) cwenv cctx oldRoot builtRoot
  mergedState = state {
    _compositeModel = newModel,
    _compositeRoot = _resultWidget mergedResult
  }
  processedResult = processWidgetResult comp mergedState wenv ctx widgetComposite mergedResult
  updatedResult = updateCompositeSize comp state wenv ctx newModel oldRoot widgetComposite

updateCompositeSize :: (Eq s, Typeable s, Typeable e) => Composite s e ep -> CompositeState s e -> WidgetEnv sp ep -> PathContext -> s -> WidgetInstance s e -> WidgetInstance sp ep -> WidgetResult sp ep
updateCompositeSize comp state wenv ctx newModel oldRoot widgetComposite = resultWidget newInstance where
  CompositeState{..} = state
  viewport = _instanceViewport widgetComposite
  renderArea = _instanceRenderArea widgetComposite
  cwenv = convertWidgetEnv wenv _compositeGlobalKeys newModel
  cctx = childContext ctx
  newRoot = _widgetResize (_instanceWidget oldRoot) cwenv viewport renderArea oldRoot _compositeSizeReq
  newState = state {
    _compositeModel = newModel,
    _compositeRoot = newRoot
  }
  newInstance = widgetComposite {
    _instanceWidget = createComposite comp newState
  }

reduceCompositeEvents :: GlobalKeys s e -> EventHandler s e ep -> s -> Seq e -> ReducedEvents s e sp ep
reduceCompositeEvents globalKeys eventHandler model events = foldl' reducer initial events where
  initial = ReducedEvents model Seq.empty Seq.empty Seq.empty Seq.empty Seq.empty
  reducer current event = foldl' reducer newCurrent newEvents where
    processed = convertResponse globalKeys current (eventHandler (_reModel current) event)
    newEvents = _reEvents processed
    newCurrent = processed { _reEvents = Seq.empty }

convertResponse :: GlobalKeys s e -> ReducedEvents s e sp ep -> EventResponse s e ep -> ReducedEvents s e sp ep
convertResponse globalKeys current@ReducedEvents{..} response = case response of
  Model newModel -> current { _reModel = newModel }
  Event event -> current { _reEvents = _reEvents |> event }
  Message key message -> case M.lookup key globalKeys of
    Just (path, _) -> current { _reMessages = _reMessages |> SendMessage path message }
    Nothing -> current
  Report report -> current { _reReports = _reReports |> report }
  Task task -> current { _reTasks = _reTasks |> task }
  Producer producer -> current { _reProducers = _reProducers |> producer }
  Multiple ehs -> foldl' (convertResponse globalKeys) current ehs

convertTasksToRequests :: Typeable e => PathContext -> Seq (IO e) -> Seq (WidgetRequest sp)
convertTasksToRequests ctx reqs = flip fmap reqs $ \req -> RunTask (_pathCurrent ctx) req

convertProducersToRequests :: Typeable e => PathContext -> Seq ((e -> IO ()) -> IO ()) -> Seq (WidgetRequest sp)
convertProducersToRequests ctx reqs = flip fmap reqs $ \req -> RunProducer (_pathCurrent ctx) req

convertRequests :: Seq (WidgetRequest s) -> Seq (WidgetRequest sp)
convertRequests reqs = fmap fromJust $ Seq.filter isJust $ fmap convertRequest reqs

convertRequest :: WidgetRequest s -> Maybe (WidgetRequest s2)
convertRequest IgnoreParentEvents = Just IgnoreParentEvents
convertRequest IgnoreChildrenEvents = Just IgnoreChildrenEvents
convertRequest Resize = Just Resize
convertRequest (SetFocus path) = Just (SetFocus path)
convertRequest (GetClipboard path) = Just (GetClipboard path)
convertRequest (SetClipboard clipboard) = Just (SetClipboard clipboard)
convertRequest ResetOverlay = Just ResetOverlay
convertRequest (SetOverlay path) = Just (SetOverlay path)
convertRequest (SendMessage path message) = Just (SendMessage path message)
convertRequest (RunTask path action) = Just (RunTask path action)
convertRequest (RunProducer path action) = Just (RunProducer path action)
convertRequest (UpdateUserState fn) = Nothing

-- | Custom Handling
compositeHandleMessage :: (Eq s, Typeable i, Typeable s, Typeable e) => Composite s e ep -> CompositeState s e -> WidgetEnv sp ep -> PathContext -> i -> WidgetInstance sp ep -> Maybe (WidgetResult sp ep)
compositeHandleMessage comp state@CompositeState{..} wenv ctx arg widgetComposite
  | isTargetReached ctx = case cast arg of
      Just evt -> Just $ processWidgetResult comp state wenv ctx widgetComposite evtResult where
        evtResult = WidgetResult Seq.empty (Seq.singleton evt) _compositeRoot
      Nothing -> Nothing
  | otherwise = fmap processEvent result where
      processEvent = processWidgetResult comp state wenv ctx widgetComposite
      cwenv = convertWidgetEnv wenv _compositeGlobalKeys _compositeModel
      nextCtx = fromJust $ moveToTarget ctx
      result = _widgetHandleMessage (_instanceWidget _compositeRoot) cwenv nextCtx arg _compositeRoot

-- Preferred size
compositePreferredSize :: CompositeState s e -> WidgetEnv sp ep -> WidgetInstance sp ep -> Tree SizeReq
compositePreferredSize CompositeState{..} wenv _ = _widgetPreferredSize widget cwenv _compositeRoot where
  widget = _instanceWidget _compositeRoot
  cwenv = convertWidgetEnv wenv _compositeGlobalKeys _compositeModel

-- Resize
compositeResize :: (Eq s, Typeable s, Typeable e) => Composite s e ep -> CompositeState s e -> WidgetEnv sp ep -> Rect -> Rect -> WidgetInstance sp ep -> Tree SizeReq -> WidgetInstance sp ep
compositeResize comp state wenv viewport renderArea widgetComposite reqs = newInstance where
  CompositeState{..} = state
  widget = _instanceWidget _compositeRoot
  cwenv = convertWidgetEnv wenv _compositeGlobalKeys _compositeModel
  newRoot = _widgetResize widget cwenv viewport renderArea _compositeRoot reqs
  newState = state {
    _compositeRoot = newRoot,
    _compositeSizeReq = reqs
  }
  newInstance = widgetComposite {
    _instanceWidget = createComposite comp newState,
    _instanceViewport = viewport,
    _instanceRenderArea = renderArea
  }

-- Render
compositeRender :: (Monad m) => CompositeState s e -> Renderer m -> WidgetEnv sp ep -> PathContext -> WidgetInstance sp ep -> m ()
compositeRender CompositeState{..} renderer wenv ctx _ = _widgetRender widget renderer cwenv cctx _compositeRoot where
  widget = _instanceWidget _compositeRoot
  cwenv = convertWidgetEnv wenv _compositeGlobalKeys _compositeModel
  cctx = childContext ctx

collectGlobalKeys :: Map WidgetKey (Path, WidgetInstance s e) -> PathContext -> WidgetInstance s e -> Map WidgetKey (Path, WidgetInstance s e)
collectGlobalKeys keys ctx widgetInstance = foldl' collectFn updatedMap pairs where
  children = _instanceChildren widgetInstance
  ctxs = Seq.fromList $ fmap (addToCurrent ctx) [0..length children]
  pairs = Seq.zip ctxs children
  collectFn current (ctxChild, child) = collectGlobalKeys current ctxChild child
  updatedMap = case _instanceKey widgetInstance of
    Just key -> M.insert key (_pathCurrent ctx, widgetInstance) keys
    _ -> keys

convertWidgetEnv :: WidgetEnv sp ep -> GlobalKeys s e -> s -> WidgetEnv s e
convertWidgetEnv wenv globalKeys model = WidgetEnv {
  _wePlatform = _wePlatform wenv,
  _weScreenSize = _weScreenSize wenv,
  _weGlobalKeys = globalKeys,
  _weModel = model,
  _weInputStatus = _weInputStatus wenv,
  _weTimestamp = _weTimestamp wenv
}
