# define Python user-defined exceptions
class SafeHavenException(Exception):
   """Base class for other exceptions"""
   pass

class CloudResourceException(SafeHavenException):
   """Raised when the input value is too small"""
   pass