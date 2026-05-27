-- check.hs — Lesson 0 verification
--
-- Running `runghc check.hs` itself proves your toolchain is alive.
-- This script then verifies you've written hello.hs correctly.

import Data.List (isInfixOf)
import System.Directory (doesFileExist)
import System.Exit (ExitCode (..), exitFailure)
import System.Process (readProcessWithExitCode)

main :: IO ()
main = do
  exists <- doesFileExist "hello.hs"
  if not exists
    then failWith "hello.hs does not exist in this directory. Create it (see README)."
    else do
      (code, out, err) <- readProcessWithExitCode "runghc" ["hello.hs"] ""
      case code of
        ExitFailure _ ->
          failWith ("hello.hs failed to compile or run. Error:\n" ++ err)
        ExitSuccess
          | "Hello, Archivist" `isInfixOf` out ->
              putStrLn "PASS \x2713 -- hello.hs runs and prints \"Hello, Archivist\"."
          | otherwise ->
              failWith ("hello.hs ran but did not print \"Hello, Archivist\".\n  Got: " ++ show out)

failWith :: String -> IO a
failWith msg = do
  putStrLn ("FAIL \x2717 -- " ++ msg)
  exitFailure
