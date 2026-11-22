submodule (solver) solver_impl
  implicit none
contains
  module function solve() result(r)
    integer :: r
    r = base + 1
  end function solve
end submodule solver_impl
