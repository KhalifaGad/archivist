-- check.hs -- Lesson 10 verification
import System.Directory (setCurrentDirectory)
import System.Exit (ExitCode (..), exitFailure)
import System.Process (rawSystem)

main :: IO ()
main = do
  setCurrentDirectory "../../.."
  putStrLn "Running: cabal test  (from repo root)"
  code <- rawSystem "cabal" ["test", "--test-show-details=streaming"]
  case code of
    ExitSuccess -> putStrLn "PASS \x2713 -- cabal test is green."
    _           -> do
      putStrLn "FAIL \x2717 -- cabal test failed. Read the output above."
      exitFailure
