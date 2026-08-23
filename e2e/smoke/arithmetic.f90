module arithmetic
  implicit none
  private

  public :: add

contains

  pure integer function add(a, b) result(value)
    integer, intent(in) :: a
    integer, intent(in) :: b

    value = a + b
  end function add

end module arithmetic
