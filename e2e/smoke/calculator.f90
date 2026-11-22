module calculator
  use arithmetic, only: add
  implicit none
  private

  public :: answer

contains

  pure integer function answer() result(value)
    value = add(20, 22)
  end function answer

end module calculator
