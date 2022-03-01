#  Entity Namespace

Contains various class definitions that match attributes and memory layouts found in the SF2 spec. Note that there are 
some classes where alignment requirements cause the size of an entity to not match that specified in the spec. These 
classes are clearly identified and they have the proper loading mechanism to accommodate the layout padding.

NOTE: these entities should be considered read-only. There is no writing facility for saving any changes made to one.
