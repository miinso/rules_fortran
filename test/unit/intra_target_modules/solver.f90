! uses a module from a sibling source, and leaves one procedure to a submodule
module solver
  use types
  implicit none
  interface
    module function solve() result(r)
      integer :: r
    end function solve
  end interface
end module solver
