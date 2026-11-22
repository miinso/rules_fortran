program physics_test
  use physics, only: light_speed
  implicit none

  if (light_speed /= 299792458) then
    write (*, *) "FAIL: expected 299792458, got", light_speed
    stop 1
  end if
end program physics_test
