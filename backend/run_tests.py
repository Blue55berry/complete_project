
import unittest
import sys
import os

def run_all_tests():
    # Add current directory to path so modules can be imported
    sys.path.append(os.getcwd())
    
    loader = unittest.TestLoader()
    start_dir = 'tests'
    suite = loader.discover(start_dir)
    
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    return result.wasSuccessful()

if __name__ == '__main__':
    success = run_all_tests()
    sys.exit(0 if success else 1)
