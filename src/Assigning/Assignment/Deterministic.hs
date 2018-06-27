module Assigning.Assignment.Deterministic where

import Data.Error
import qualified Data.Set as Set
import Data.Span
import Prologue

class (Alternative (f s), Ord s, Show s) => Assigning f s where
  sym :: s -> f s s

combine :: Ord s => Bool -> Set s -> Set s -> Set s
combine e s1 s2 = if e then s1 <> s2 else lowerBound

type State s = [s]

data Offset = Offset
  { offsetBytes :: {-# UNPACK #-} !Int
  , offsetPos   :: {-# UNPACK #-} !Pos
  }
  deriving (Eq, Ord, Show)

instance Lower Offset where
  lowerBound = Offset 0 lowerBound

type Table s a = [(s, a)]

data DetPar s a = DetPar
  { isNullable :: Bool
  , firstSet   :: Set s
  , match      :: State s -> Set s -> Either (Error s) (State s, a)
  }
  deriving (Functor)

instance Ord s => Applicative (DetPar s) where
  pure a = DetPar True lowerBound (\ inp _ -> Right (inp, a))
  DetPar n1 f1 p1 <*> ~(DetPar n2 f2 p2) = DetPar (n1 && n2) (combine n1 f1 f2) (p1 `pseq` p2)
    where p1 `pseq` p2 = \ inp follow -> do
            (inp1, v1) <- p1 inp (combine n2 f2 follow)
            (inp2, v2) <- p2 inp1 follow
            let res = v1 v2
            res `seq` pure (inp2, res)

instance Ord s => Alternative (DetPar s) where
  empty = DetPar False lowerBound (\ s _ -> Left (Error lowerBound [] (listToMaybe s)))
  DetPar n1 f1 p1 <|> DetPar n2 f2 p2 = DetPar (n1 || n2) (f1 <> f2) (p1 `palt` p2)
    where p1 `palt` p2 = p
            where p [] follow =
                    if      n1 then p1 [] follow
                    else if n2 then p2 [] follow
                    else Left (Error lowerBound (toList (f1 <> f2)) Nothing)
                  p inp@(s:_) follow =
                    if      s `Set.member` f1 then p1 inp follow
                    else if s `Set.member` f2 then p2 inp follow
                    else if n1 && s `Set.member` follow then p1 inp follow
                    else if n2 && s `Set.member` follow then p2 inp follow
                    else Left (Error lowerBound (toList (combine n1 f1 follow <> combine n2 f2 follow)) (Just s))

instance (Ord s, Show s) => Assigning DetPar s where
  sym s = DetPar False (Set.singleton s) (\ ss _ -> case ss of
    []    -> Left (Error lowerBound [s] Nothing)
    _:inp -> Right (inp, s))

invokeDet :: DetPar s a -> State s -> Either (Error s) a
invokeDet (DetPar _ _ p) inp = snd <$> p inp lowerBound
