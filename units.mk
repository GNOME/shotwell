
# List of all units in the system.  Use directory name rather than namespace.
#
# This list is primarily used at compile time to build the executable.
#
# NOTE: In all unit listings, the unit-unit must be first.  Units may follow in any order
# thereafter.
UNITS = \
	unit \
	util \
	threads \
	db \
	plugins

# Names of variables (which follow) that represent unit groups for different uses of the
# application.  The variables should be formed as Name_UNITS.  Entry and terminate points in
# the code will be Name.unitize_init() and Name.unitize_terminate().
#
# These lists are used primarily at run-time to initialize the proper units depending on the mode
# the executable starts in.
#
# Note that these names can be the names of units as well.  In that case, the init and terminate
# code will be placed in that unit's namespace.
APP_GROUPS = Library Direct

# List of units for library mode.
Library_UNITS = \
	unit \
	util \
	threads \
	db \
	plugins

# List of units for direct-edit mode.
Direct_UNITS = \
	unit \
	util \
	threads \
	db

