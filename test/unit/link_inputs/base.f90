! called only from glue.c, never from the fortran main
subroutine only_glue(n) bind(C, name="only_glue")
  use iso_c_binding
  implicit none
  integer(c_int), intent(out) :: n
  n = 5
end subroutine only_glue
