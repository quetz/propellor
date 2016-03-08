{-# LANGUAGE TypeOperators, PolyKinds, DataKinds, TypeFamilies, UndecidableInstances #-}

module Propellor.Types.OS.TypeLevel (
	SupportedOS(..),
	OSList(..),
	debian,
	buntish,
	freeBSD,
	unixlike,
	combineSupportedOS,
	intersectSupportedOS,
) where

import Network.BSD (HostName)
import Data.Typeable
import Data.String
import Data.Type.Bool
import Data.Type.Equality

-- | A supported operating system.
data SupportedOS = OSDebian | OSBuntish | OSFreeBSD
	deriving (Show, Eq)

-- | A type-level and value-level list of supported operating systems.
--
-- If the list is empty, no operating system is supported.
data OSList (os :: [SupportedOS]) = OSList [SupportedOS]
	deriving (Show, Eq)

-- | Any unix-like OS.
unixlike :: OSList '[OSDebian, OSBuntish, OSFreeBSD]
unixlike = OSList [OSDebian, OSBuntish, OSFreeBSD]

debian :: OSList '[OSDebian]
debian = typeOS OSDebian

buntish :: OSList '[OSBuntish]
buntish = typeOS OSBuntish

freeBSD :: OSList '[OSFreeBSD]
freeBSD = typeOS OSFreeBSD

typeOS :: SupportedOS -> OSList os
typeOS o = OSList [o]

-- FIXME, should type check
-- foo :: OSList '[OSDebian, OSFreeBSD]
-- foo = (debian `combineSupportedOS` freeBSD ) `intersectSupportedOS` unixlike 

-- | Combines two lists of supported OS's, yielding a list with the
-- contents of both.
combineSupportedOS
	:: (r ~ ConcatOSList l1 l2)
	=> OSList l1
	-> OSList l2
	-> OSList r
combineSupportedOS (OSList l1) (OSList l2) = OSList (l1 ++ l2)

-- | Type level concat for OSList.
type family ConcatOSList (list1 :: [a]) (list2 :: [a]) :: [a]
type instance ConcatOSList '[] list2 = list2
type instance ConcatOSList (a ': rest) list2 = a ': ConcatOSList rest list2

-- | The intersection between two lists of supported OS's.
intersectSupportedOS
	:: (r ~ IntersectOSList '[] l1 l2)
	=> OSList l1
	-> OSList l2
	-> OSList r
intersectSupportedOS (OSList l1) (OSList l2) = OSList (filter (`elem` l2) l1)

-- | Type level intersection for OSList
type family IntersectOSList (coll :: [a]) (list1 :: [a]) (list2 :: [a]) :: [a]
type instance IntersectOSList coll '[] list2 = coll
type instance IntersectOSList coll (a ': rest) list2 = 
	If (ElemOSList a list2)
		(IntersectOSList (a ': coll) rest list2)
		(IntersectOSList coll rest list2)

-- | Type level elem for OSList
type family ElemOSList a (list :: [b]) :: Bool
type instance ElemOSList a '[] = False
type instance ElemOSList a (b ': bs) = 
	If (a == b)
		True
		(ElemOSList a bs)

-- | Type level equality for SupportedOS
type family EqOS (a :: SupportedOS) (b :: SupportedOS) where
	EqOS a a = True
	EqOS a b = False
type instance a == b = EqOS a b
