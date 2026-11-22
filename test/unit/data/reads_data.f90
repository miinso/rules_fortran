program reads_data
  implicit none
  integer :: unit, ios, value

  ! tests run from the runfiles root, so the path is workspace-relative
  open (newunit=unit, file="test/unit/data/input.txt", status="old", action="read", iostat=ios)
  if (ios /= 0) then
    write (*, *) "FAIL: cannot open data file, iostat =", ios
    stop 1
  end if

  read (unit, *) value
  close (unit)

  if (value /= 42) then
    write (*, *) "FAIL: expected 42, got", value
    stop 1
  end if
end program reads_data
