! fails unless RULES_FORTRAN_ENV_PROBE is set to "expected" in the test's environment
program env_check
  implicit none
  character(len=64) :: value
  integer :: status

  call get_environment_variable("RULES_FORTRAN_ENV_PROBE", value, status=status)
  if (status /= 0) error stop 1
  if (trim(value) /= "expected") error stop 2
end program env_check
