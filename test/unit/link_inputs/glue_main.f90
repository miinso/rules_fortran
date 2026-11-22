program glue_main
  use iso_c_binding
  implicit none
  interface
    function glue_fn() bind(C, name="glue_fn") result(r)
      import :: c_int
      integer(c_int) :: r
    end function glue_fn
  end interface
  if (glue_fn() /= 5) error stop 1
end program glue_main
