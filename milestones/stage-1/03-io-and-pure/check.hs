-- check.hs — Lesson 3 verification
-- Runs your Main.hs as a subprocess and checks that the output
-- contains the expected payload strings, in order.

import Control.Monad (unless)
import Data.List (isInfixOf)
import System.Directory (doesFileExist)
import System.Exit (ExitCode (..), exitFailure)
import System.Process (readProcessWithExitCode)

main :: IO ()
main = do
  haveArch <- doesFileExist "Archivist.hs"
  unless haveArch $
    failWith "Archivist.hs is missing -- copy it over from Lesson 2."

  haveMain <- doesFileExist "Main.hs"
  unless haveMain $
    failWith "Main.hs does not exist. Create it (see README)."

  (code, out, err) <- readProcessWithExitCode "runghc" ["Main.hs"] ""
  case code of
    ExitFailure _ ->
      failWith ("Main.hs failed to compile or run. Error:\n" ++ err)
    ExitSuccess -> do
      check "output mentions the stream id 'orders'" ("orders"           `isInfixOf` out) out
      check "output contains payload 'order-placed'"  ("order-placed"     `isInfixOf` out) out
      check "output contains payload 'payment-received'" ("payment-received" `isInfixOf` out) out

      -- Order matters: order-placed must appear before payment-received
      let i1 = indexOf "order-placed" out
          i2 = indexOf "payment-received" out
      check "events are printed in append order (oldest first)"
            (i1 >= 0 && i2 >= 0 && i1 < i2) out

      putStrLn "PASS \x2713 -- Lesson 3 complete."

check :: String -> Bool -> String -> IO ()
check desc True  _   = putStrLn ("  \x2713 " ++ desc)
check desc False out = do
  putStrLn ("  \x2717 " ++ desc)
  putStrLn ("    Got output:\n" ++ unlines (map ("      " ++) (lines out)))
  exitFailure

failWith :: String -> IO a
failWith m = do
  putStrLn ("FAIL \x2717 -- " ++ m)
  exitFailure

-- Tiny helper: index of the first occurrence of needle in haystack, or -1.
indexOf :: String -> String -> Int
indexOf needle = go 0
  where
    go _ [] = -1
    go n s@(_:rest)
      | needle `isPrefixOf'` s = n
      | otherwise              = go (n + 1) rest

    isPrefixOf' :: String -> String -> Bool
    isPrefixOf' []     _      = True
    isPrefixOf' _      []     = False
    isPrefixOf' (x:xs) (y:ys) = x == y && isPrefixOf' xs ys
