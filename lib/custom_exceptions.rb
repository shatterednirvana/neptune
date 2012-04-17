# Programmer: Chris Bunch

# A special class of exceptions that are thrown whenever the AppController
# experiences an unexpected result.
class AppControllerException < Exception
end


# A class of exceptions that are thrown when the user tries to run a Neptune
# job but fails to give us the correct parameters to do so.
class BadConfigurationException < Exception
end


# An exception that is thrown whenever the user specifies a file to use
# that does not exist.
class FileNotFoundException < Exception
end
