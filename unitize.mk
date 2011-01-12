# unitize.mk
#
# Post-processes each unit's .mk file to properly add its requirements to the master Makefile.

# append files to SRC_FILES (*don't* use +=, that's a recursive append)
UNITIZED_SRC_FILES := $(UNITIZED_SRC_FILES) src/$(UNIT_DIR)/$(UNIT_NAME).vala $(foreach file,$(UNIT_FILES),src/$(UNIT_DIR)/$(file))

# append unit namespace to master list
UNIT_NAMESPACES := $(UNIT_NAMESPACES) $(UNIT_NAME)

# append unit resources to master list
UNIT_RESOURCES := $(UNIT_RESOURCES) $(foreach rc,$(UNIT_RC),src/$(UNIT_DIR)/$(rc))

# create custom uses lists for this unit; note that the unit-unit is automatically included
# (unless the unit is the unit-unit)
ifneq ($(UNIT_NAME),Unit)
$(UNIT_NAME)_USES := Unit $(UNIT_USES)
else
$(UNIT_NAME)_USES := $(UNIT_USES)
endif
$(UNIT_NAME)_USES_INITS := $(foreach uses,$($(UNIT_NAME)_USES),$(uses).init_entry();)
$(UNIT_NAME)_USES_TERMINATORS := $(foreach uses,$($(UNIT_NAME)_USES),$(uses).terminate_entry();)

# clear unit variables so they are not appended to by the next unit
UNIT_NAME=
UNIT_DIR=
UNIT_FILES=
UNIT_USES=
UNIT_RC=
