program main
  use vendor
  implicit none
  if (vendor_value() /= 42) error stop 1
end program main
