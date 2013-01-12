
# List of all units in the system.  Use directory name rather than namespace.
#
# This list is primarily used at compile time to build the executable.
#
# NOTE: The unit-unit must be first.  Units may follow in any order thereafter.
#
# NOTE: Be sure to add the unit to the appropriate APP_UNITS .mk file.
UNITS = \
	unit \
	util \
	threads \
	db \
	editing_tools \
	plugins \
	slideshow \
	photos \
	publishing \
	library \
	direct \
	core \
	sidebar \
	events \
	tags \
	camera \
	searches \
	config \
	data_imports \
	folders

# Name(s) of units that represent application entry points.  These units will have init and
# termination entry points generated: Name.unitize_init() and Name.unitize_terminate().  These
# methods should be called in main().  They will initialize the named unit and all is prerequisite
# units, thereby initializing the entire application.
APP_UNITS = Library Direct
