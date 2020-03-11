"""
AIDA ontology container
"""

__author__  = "Shahzad Rajput <shahzad.rajput@nist.gov>"
__status__  = "production"
__version__ = "0.0.0.1"
__date__    = "11 February 2020"

from aida.container import Container
from aida.entity_spec import EntitySpec
from aida.event_spec import EventSpec
from aida.file_handler import FileHandler
from aida.object import Object
from aida.relation_spec import RelationSpec

class Ontology(Object):
    def __init__(self, logger, entities_ontology_filename, relations_ontology_filename, events_ontology_filename):
        super().__init__(logger)
        self.entities_ontology_filename = entities_ontology_filename
        self.relations_ontology_filename = relations_ontology_filename
        self.events_ontology_filename = events_ontology_filename
        self.entities = Container(logger)
        self.relations = Container(logger)
        self.events = Container(logger)
        self.load('entities', EntitySpec, entities_ontology_filename, self.entities)
        self.load('relations', RelationSpec, relations_ontology_filename, self.relations)
        self.load('events', EventSpec, events_ontology_filename, self.events)
    
    def load(self, ere, ere_spec, ere_filename, ere_container):
        for entry in FileHandler(self.logger, ere_filename, encoding='ISO-8859-1'):
            ontology_id = entry.get('AnnotIndexID')
            ere_container.add(key=ontology_id, value=ere_spec(self.get('logger'), entry))