{-
Copyright 2016 SlamData, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}

module SlamData.Quasar.Auth.Store where

import Prelude
import Control.Monad.Eff (Eff)
import Data.Either (Either)
import DOM (DOM)
import OIDC.Crypt.Types as OIDCT
import Quasar.Advanced.Types as QAT
import SlamData.Quasar.Auth.Keys as AuthKeys
import Utils.LocalStorage as LS

storeIdToken ∷ ∀ e. Either String OIDCT.IdToken → Eff (dom ∷ DOM | e) Unit
storeIdToken idToken =
  LS.setLocalStorage
    AuthKeys.idTokenLocalStorageKey
    $ OIDCT.runIdToken <$> idToken

storeProvider ∷ ∀ e. QAT.Provider → Eff (dom ∷ DOM | e) Unit
storeProvider =
  LS.setLocalStorage AuthKeys.providerLocalStorageKey

clearProvider ∷ ∀ e. Eff (dom ∷ DOM | e) Unit
clearProvider =
  LS.removeLocalStorage AuthKeys.providerLocalStorageKey

storeKeyString ∷ ∀ e. OIDCT.KeyString → Eff (dom ∷ DOM |e) Unit
storeKeyString (OIDCT.KeyString ks) =
  LS.setLocalStorage
    AuthKeys.keyStringLocalStorageKey
    ks

storeNonce ∷ ∀ e. OIDCT.UnhashedNonce → Eff (dom ∷ DOM |e) Unit
storeNonce (OIDCT.UnhashedNonce n) =
  LS.setLocalStorage
    AuthKeys.nonceLocalStorageKey
    n

clearIdToken ∷ ∀ e. Eff (dom ∷ DOM |e) Unit
clearIdToken =
  LS.removeLocalStorage AuthKeys.idTokenLocalStorageKey
