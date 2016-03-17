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

module SlamData.AuthRedirect
  ( main
  ) where

import SlamData.Prelude

import Control.Monad.Aff as Aff
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Console as Console
import Control.Monad.Eff.Exception as Exn
import Control.Monad.Maybe.Trans as MBT

import Data.Foldable as F

import DOM as DOM
import DOM.HTML (window)
import DOM.HTML.Location as Loc
import DOM.HTML.Window as Win

import Network.HTTP.Affjax as AX

import OIDCCryptUtils as OIDC

import Quasar.Aff as Quasar
import Quasar.Auth as Auth
import Quasar.Auth.OpenIDConfiguration (getOpenIDConfiguration)
import Quasar.Auth.Provider (Provider(..))

import SlamData.AuthRedirect.RedirectHashPayload as Payload

type RedirectEffects =
  Quasar.RetryEffects
    ( console :: Console.CONSOLE
    , err :: Exn.EXCEPTION
    , dom :: DOM.DOM
    , rsaSignTime :: OIDC.RSASIGNTIME
    , ajax :: AX.AJAX
    )

type RedirectState =
  { payload :: Payload.RedirectHashPayload
  , keyString :: OIDC.KeyString
  , unhashedNonce :: OIDC.UnhashedNonce
  , clientID :: OIDC.ClientID
  }

retrieveRedirectState :: Eff RedirectEffects RedirectState
retrieveRedirectState = do
  hash <- window >>= Win.location >>= Loc.hash

  payload <-
    Payload.parseUriHash hash #
      either (Exn.throw <<< show) pure

  keyString <-
    Auth.retrieveKeyString >>=
      maybe (Exn.throw "Failed to retrieve KeyString from local storage") pure

  unhashedNonce <-
    Auth.retrieveNonce >>=
      maybe (Exn.throw "Failed to retrieve UnhashedNonce from local storage") pure

  clientID <-
    Auth.retrieveClientID >>=
      maybe (Exn.throw "Failed to retrieve ClientID from local storage") pure

  pure
    { payload
    , keyString
    , unhashedNonce
    , clientID
    }

newtype RedirectURL = RedirectURL String

verifyRedirect
  :: RedirectState
  -> OIDC.Issuer
  -> OIDC.JSONWebKey
  -> MBT.MaybeT (Eff RedirectEffects) RedirectURL
verifyRedirect st issuer jwk = do
  -- Fail immediately if the IdToken fails to verify.
  OIDC.verifyIdToken st.payload.idToken issuer st.clientID st.unhashedNonce jwk
    # lift
    >>= guard
  -- If the IdToken has been verified,
  -- then we may proceed to extract the redirect URL.

  OIDC.unbindState st.payload.state st.keyString
    <#> OIDC.runStateString
    >>> RedirectURL
      # pure
      # MBT.MaybeT



main :: Eff RedirectEffects Unit
main = do
  -- We're getting token too fast. It isn't valid until next second (I think)
  Aff.runAff Exn.throwException (\_ -> pure unit)  do
    state <- liftEff retrieveRedirectState
    -- First, retrieve the provider that matches our stored ClientID.
    Provider provider <- do
      providers <-
        Quasar.retrieveAuthProviders
          >>= maybe
                (liftEff
                 $ Exn.throw "Failed to retrieve auth providers from Quasar")
                pure

      F.find (\(Provider pr) -> pr.clientID == state.clientID) providers
        # maybe
            (liftEff
             $ Exn.throw
             $ "Could not find provider matching client ID '"
             <> OIDC.runClientID state.clientID <> "'")
            pure

    let openIDConfiguration =
          getOpenIDConfiguration provider.openIDConfiguration

    liftEff do
      -- Try to verify the IdToken against each of the provider's jwks,
      -- stopping at the first success.
      RedirectURL redirectURL <-
        openIDConfiguration.jwks
          <#> verifyRedirect state openIDConfiguration.issuer
            # foldl ((<|>)) empty
            # MBT.runMaybeT
          >>= maybe (Exn.throw "Failed to verify redirect") pure


      Auth.storeIdToken state.payload.idToken
      window
        >>= Win.location
        >>= Loc.setHref redirectURL
