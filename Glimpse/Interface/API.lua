local _, ns = ...

--- What other addons may call: the one global this addon creates.
--
--   Glimpse.Provide(kind, provider)   offer previews of a kind in this addon's
--                                     frames; `Providers` says what a provider is
--
-- An addon calling it at its own load lists this one in its `OptionalDeps`, so
-- this one has loaded first.
_G.Glimpse = { Provide = ns.Providers.Provide }
