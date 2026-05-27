-- check.hs -- Lesson 4 verification
-- From L4 onward the real project lives at the repo root.
-- This script cd's there and runs cabal test.

import System.Directory (setCurrentDirectory)
import System.Exit (ExitCode (..), exitFailure)
import System.Process (rawSystem)

main :: IO ()
main = do
  setCurrentDirectory "../../.."   -- milestones/stage-1/04-cabal-project -> repo root
  putStrLn "Running: cabal test  (from repo root)"
  code <- rawSystem "cabal" ["test", "--test-show-details=streaming"]
  case code of
    ExitSuccess -> putStrLn "PASS \x2713 -- cabal test is green."
    _           -> do
      putStrLn "FAIL \x2717 -- cabal test failed. Read the output above."
      exitFailure
