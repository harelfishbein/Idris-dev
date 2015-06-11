module Prelude.Cast

import Prelude.Bool
import public Builtins

||| Type class for transforming a instance of a data type to another type.
class Cast from to where
    ||| Perform a cast operation.
    |||
    ||| @orig The original type.
    cast : (orig : from) -> to

-- General casts

instance Cast a a where
    cast = id

-- String casts

instance Cast String Int where
    cast = prim__fromStrInt

instance Cast String Float where
    cast = prim__strToFloat

instance Cast String Integer where
    cast = prim__fromStrBigInt

-- Int casts

instance Cast Int String where
    cast = prim__toStrInt

instance Cast Int Float where
    cast = prim__toFloatInt

instance Cast Int Integer where
    cast = prim__sextInt_BigInt

-- Float casts

instance Cast Float String where
    cast = prim__floatToStr

instance Cast Float Int where
    cast = prim__fromFloatInt

-- Integer casts

instance Cast Integer String where
    cast = prim__toStrBigInt

-- Char casts

instance Cast Char Int where
    cast = prim__charToInt
