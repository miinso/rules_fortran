program mixed_main
  implicit none
  integer, external :: legacy
  if (legacy() /= 21) error stop 1
end program mixed_main
