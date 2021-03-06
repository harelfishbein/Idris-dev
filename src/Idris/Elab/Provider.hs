{-# LANGUAGE PatternGuards #-}
module Idris.Elab.Provider(elabProvider) where

import Idris.AbsSyntax
import Idris.ASTUtils
import Idris.DSL
import Idris.Error
import Idris.Delaborate
import Idris.Imports
import Idris.Coverage
import Idris.DataOpts
import Idris.Providers
import Idris.Primitives
import Idris.Inliner
import Idris.PartialEval
import Idris.DeepSeq
import Idris.Output (iputStrLn, pshow, iWarn)
import IRTS.Lang

import Idris.Elab.Type
import Idris.Elab.Clause
import Idris.Elab.Value
import Idris.Elab.Utils
import Idris.Elab.Term

import Idris.Core.TT
import Idris.Core.Elaborate hiding (Tactic(..))
import Idris.Core.Evaluate
import Idris.Core.Execute
import Idris.Core.Typecheck
import Idris.Core.CaseTree

import Idris.Docstrings

import Prelude hiding (id, (.))
import Control.Category

import Control.Applicative hiding (Const)
import Control.DeepSeq
import Control.Monad
import Control.Monad.State.Strict as State
import Data.List
import Data.Maybe
import Debug.Trace

import qualified Data.Map as Map
import qualified Data.Set as S
import qualified Data.Text as T
import Data.Char(isLetter, toLower)
import Data.List.Split (splitOn)

import Util.Pretty(pretty, text)

-- | Elaborate a type provider
elabProvider :: Docstring (Either Err PTerm) -> ElabInfo -> SyntaxInfo -> FC -> ProvideWhat -> Name -> Idris ()
elabProvider doc info syn fc what n
    = do i <- getIState
         -- Ensure that the experimental extension is enabled
         unless (TypeProviders `elem` idris_language_extensions i) $
           ifail $ "Failed to define type provider \"" ++ show n ++
                   "\".\nYou must turn on the TypeProviders extension."

         ctxt <- getContext

         -- First elaborate the expected type (and check that it's a type)
         -- The goal type for a postulate is always Type.
         (ty', typ) <- case what of
                         ProvTerm ty p   -> elabVal info ERHS ty
                         ProvPostulate _ -> elabVal info ERHS (PType fc)
         unless (isTType typ) $
           ifail ("Expected a type, got " ++ show ty' ++ " : " ++ show typ)

         -- Elaborate the provider term to TT and check that the type matches
         (e, et) <- case what of
                      ProvTerm _ tm    -> elabVal info ERHS tm
                      ProvPostulate tm -> elabVal info ERHS tm
         unless (isProviderOf ctxt ty' et) $
           ifail $ "Expected provider type " ++ show (providerOf ty') ++
                   ", got " ++ show et ++ " instead."

         -- Execute the type provider and normalise the result
         -- use 'run__provider' to convert to a primitive IO action

         rhs <- execute (mkApp (P Ref (sUN "run__provider") Erased)
                                          [Erased, e])
         let rhs' = normalise ctxt [] rhs
         logLvl 3 $ "Normalised " ++ show n ++ "'s RHS to " ++ show rhs

         -- Extract the provided term or postulate from the type provider
         provided <- getProvided fc rhs'

         case provided of
           Provide tm
             | ProvTerm ty _ <- what ->
               do -- Finally add a top-level definition of the provided term
                  elabType info syn doc [] fc [] n NoFC ty
                  elabClauses info fc [] n [PClause fc n (PApp fc (PRef fc n) []) [] (delab i tm) []]
                  logLvl 3 $ "Elaborated provider " ++ show n ++ " as: " ++ show tm
             | ProvPostulate _ <- what ->
               do -- Add the postulate
                  elabPostulate info syn doc fc [] n (delab i tm)
                  logLvl 3 $ "Elaborated provided postulate " ++ show n
             | otherwise ->
               ierror . Msg $ "Attempted to provide a postulate where a term was expected."

    where isTType :: TT Name -> Bool
          isTType (TType _) = True
          isTType _ = False

          -- Note: IO (Providers.Provider ty) is used instead of IO'
          -- (MkFFI C_FFI) (Providers.Provider ty) in hopes of better
          -- error messages with less normalisation
          providerOf :: Type -> Type
          providerOf ty = App Complete (P Ref (sUN "IO") Erased) $
                            App Complete (P Ref (sNS (sUN "Provider") ["Providers", "Prelude"]) Erased)
                              ty

          isProviderOf :: Context -> TT Name -> TT Name -> Bool
          isProviderOf ctxt tp prov =
            case converts ctxt [] (providerOf tp) prov of
              OK _ -> True
              _    -> False
