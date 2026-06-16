extends GdUnitTestSuite

## Characterization tests for ActionHandler's pure static zone math
## (rules 5.13.2 retreat and 5.15.1.1 counter-retreat).


func test_retreat_zone_moves_back_one() -> void:
	assert_int(ActionHandler.get_retreat_zone(8)).is_equal(7)
	assert_int(ActionHandler.get_retreat_zone(5)).is_equal(4)
	assert_int(ActionHandler.get_retreat_zone(2)).is_equal(1)


func test_retreat_zone_floors_at_one() -> void:
	assert_int(ActionHandler.get_retreat_zone(1)).is_equal(1)


func test_counter_retreat_only_moves_zones_6_to_8() -> void:
	assert_int(ActionHandler.get_counter_retreat_zone(6)).is_equal(5)
	assert_int(ActionHandler.get_counter_retreat_zone(7)).is_equal(4)
	assert_int(ActionHandler.get_counter_retreat_zone(8)).is_equal(3)


func test_counter_retreat_zones_1_to_5_stay_put() -> void:
	for zone in range(1, 6):
		assert_int(ActionHandler.get_counter_retreat_zone(zone)).is_equal(zone)
