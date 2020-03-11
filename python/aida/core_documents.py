"""
AIDA CoreDocuments class.
"""

__author__  = "Shahzad Rajput <shahzad.rajput@nist.gov>"
__status__  = "production"
__version__ = "0.0.0.1"
__date__    = "15 January 2020"

from aida.container import Container
from aida.file_handler import FileHandler

import re

class CoreDocuments(Container):
    """
    AIDA CoreDocuments class.
    """

    def __init__(self, logger, filename):
        super().__init__(logger)
        self.filename = filename
        self.load()
        
    def load(self):
        """
        Load the file containing core documents into the container
        """
        for entry in FileHandler(self.logger, self.filename):
            docid = entry.get('root_id')
            self.add(key=docid, value=docid)