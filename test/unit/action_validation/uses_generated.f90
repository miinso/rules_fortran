module uses_generated
  implicit none
  include 'params.h'
contains
  integer function answer()
    answer = generated_n
  end function answer
end module uses_generated
