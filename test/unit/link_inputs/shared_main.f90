! calls into a library that exists only as a shared object, so the loader
! has to find it when the program starts
program shared_main
  use iso_c_binding
  implicit none
  interface
    function shared_fn() bind(C, name="shared_fn") result(r)
      import :: c_int
      integer(c_int) :: r
    end function shared_fn
  end interface
  if (shared_fn() /= 9) error stop 1
end program shared_main
