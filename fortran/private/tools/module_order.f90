! module_order: works out in which order the sources of one target must be
! seen so that every MODULE is compiled before the sources that USE it.
!
! usage: module_order <params file>
!   line 1 of the params file: path of the order file to write
!   line 2: path of an empty source file to write
!   lines 3..: the target's source files
!
! the order file is a compiler response file: the empty source first (so it
! is never empty), then every source that defines a module or submodule,
! each after the sources whose modules it uses. sources that define no
! module are left out: nothing needs them compiled first.
!
! this is a line scanner, not a parser. it reads `module x`, `submodule (p) x`
! and `use x` at the start of a statement, and ignores the preprocessor: a USE
! inside an inactive #if still counts, which can only add an ordering constraint.
program module_order
  use, intrinsic :: iso_fortran_env, only: error_unit
  implicit none

  integer, parameter :: max_line = 4096

  type :: string
    character(len=:), allocatable :: s
  end type string

  type :: source
    character(len=:), allocatable :: path
    type(string), allocatable :: provides(:)
    type(string), allocatable :: needs(:)
    integer :: state = 0  ! 0 = not visited, 1 = being visited, 2 = done
  end type source

  character(len=:), allocatable :: params_path, order_path, empty_path
  type(string), allocatable :: lines(:)
  type(source), allocatable :: sources(:)
  integer, allocatable :: sorted(:)
  integer :: i, n_sorted, unit

  call get_argument(1, params_path)
  call read_lines(params_path, lines)
  if (size(lines) < 2) call die("params file needs an order path and an empty source path")
  order_path = lines(1)%s
  empty_path = lines(2)%s

  allocate(sources(size(lines) - 2))
  do i = 1, size(sources)
    sources(i)%path = lines(i + 2)%s
    allocate(sources(i)%provides(0), sources(i)%needs(0))
    call scan_source(sources(i))
  end do

  call check_duplicates()

  allocate(sorted(size(sources)))
  n_sorted = 0
  do i = 1, size(sources)
    if (size(sources(i)%provides) > 0) call visit(i)
  end do

  open(newunit=unit, file=empty_path, status="replace", action="write")
  close(unit)

  open(newunit=unit, file=order_path, status="replace", action="write")
  write(unit, "(A)") quoted(empty_path)
  do i = 1, n_sorted
    write(unit, "(A)") quoted(sources(sorted(i))%path)
  end do
  close(unit)

contains

  subroutine die(message)
    character(len=*), intent(in) :: message
    write(error_unit, "(A)") "module_order: " // message
    error stop 1
  end subroutine die

  subroutine get_argument(position, value)
    integer, intent(in) :: position
    character(len=:), allocatable, intent(out) :: value
    integer :: length
    call get_command_argument(position, length=length)
    if (length == 0) call die("usage: module_order <params file>")
    allocate(character(len=length) :: value)
    call get_command_argument(position, value)
  end subroutine get_argument

  subroutine push(list, value)
    type(string), allocatable, intent(inout) :: list(:)
    character(len=*), intent(in) :: value
    type(string), allocatable :: grown(:)
    integer :: k
    do k = 1, size(list)
      if (list(k)%s == value) return
    end do
    allocate(grown(size(list) + 1))
    grown(1:size(list)) = list
    grown(size(list) + 1)%s = value
    call move_alloc(grown, list)
  end subroutine push

  subroutine read_lines(path, list)
    character(len=*), intent(in) :: path
    type(string), allocatable, intent(out) :: list(:)
    type(string), allocatable :: grown(:)
    character(len=max_line) :: buffer
    integer :: unit, status, count
    allocate(list(64))
    count = 0
    open(newunit=unit, file=path, status="old", action="read", iostat=status)
    if (status /= 0) call die("cannot open " // path)
    do
      read(unit, "(A)", iostat=status) buffer
      if (status /= 0) exit
      call clean(buffer)
      if (len_trim(buffer) == 0) cycle
      if (count == size(list)) then
        allocate(grown(2 * size(list)))
        grown(1:count) = list(1:count)
        call move_alloc(grown, list)
      end if
      count = count + 1
      list(count)%s = trim(buffer)
    end do
    close(unit)
    list = list(1:count)
  end subroutine read_lines

  ! tabs and carriage returns (crlf sources) become blanks
  subroutine clean(text)
    character(len=*), intent(inout) :: text
    integer :: k
    do k = 1, len(text)
      if (text(k:k) == achar(9) .or. text(k:k) == achar(13)) text(k:k) = " "
    end do
  end subroutine clean

  subroutine lower(text)
    character(len=*), intent(inout) :: text
    integer :: k, code
    do k = 1, len(text)
      code = iachar(text(k:k))
      if (code >= iachar("A") .and. code <= iachar("Z")) text(k:k) = achar(code + 32)
    end do
  end subroutine lower

  ! length of the identifier text starts with (0 if it starts with none)
  integer function name_length(text)
    character(len=*), intent(in) :: text
    integer :: k
    name_length = 0
    do k = 1, len(text)
      if (verify(text(k:k), "abcdefghijklmnopqrstuvwxyz0123456789_") /= 0) exit
      name_length = k
    end do
  end function name_length

  logical function is_fixed_form(path)
    character(len=*), intent(in) :: path
    integer :: n
    n = len(path)
    is_fixed_form = .false.
    if (n >= 2) is_fixed_form = path(n - 1:n) == ".f" .or. path(n - 1:n) == ".F"
  end function is_fixed_form

  subroutine scan_source(src)
    type(source), intent(inout) :: src
    character(len=max_line) :: buffer
    integer :: unit, status, start, stop_at
    logical :: fixed
    fixed = is_fixed_form(src%path)
    open(newunit=unit, file=src%path, status="old", action="read", iostat=status)
    if (status /= 0) call die("cannot open " // src%path)
    do
      read(unit, "(A)", iostat=status) buffer
      if (status /= 0) exit
      ! fixed form: a comment has c, * or ! in column 1
      if (fixed .and. scan(buffer(1:1), "cC*!") /= 0) cycle
      call clean(buffer)
      call lower(buffer)
      ! drop a trailing comment, then take the statements one by one
      stop_at = index(buffer, "!")
      if (stop_at > 0) buffer(stop_at:) = " "
      start = 1
      do
        stop_at = index(buffer(start:), ";")
        if (stop_at == 0) then
          call statement(src, adjustl(buffer(start:)))
          exit
        end if
        call statement(src, adjustl(buffer(start:start + stop_at - 2)))
        start = start + stop_at
        if (start > len(buffer)) exit
      end do
    end do
    close(unit)
  end subroutine scan_source

  subroutine statement(src, text)
    type(source), intent(inout) :: src
    character(len=*), intent(in) :: text
    character(len=max_line) :: rest, inside
    integer :: n, colons, close_at, colon

    if (text(1:7) == "module ") then
      ! `module x` and nothing after it. `module procedure x`, `module function f()`
      ! and friends have more words and are not module statements
      rest = adjustl(text(8:))
      n = name_length(rest)
      if (n == 0) return
      if (len_trim(rest(n + 1:)) > 0) return
      if (rest(1:n) == "procedure") return
      call push(src%provides, rest(1:n))
    else if (text(1:9) == "submodule") then
      ! submodule (parent) x   or   submodule (parent:ancestor) x
      rest = adjustl(text(10:))
      if (rest(1:1) /= "(") return
      close_at = index(rest, ")")
      if (close_at == 0) return
      inside = adjustl(rest(2:close_at - 1))
      rest = adjustl(rest(close_at + 1:))
      n = name_length(rest)
      if (n == 0) return
      colon = index(inside, ":")
      if (colon == 0) then
        call push(src%needs, trim(inside))
        call push(src%provides, trim(inside) // ":" // rest(1:n))
      else
        call push(src%needs, trim(inside(1:colon - 1)))
        call push(src%needs, trim(inside(1:colon - 1)) // ":" // trim(adjustl(inside(colon + 1:))))
        call push(src%provides, trim(inside(1:colon - 1)) // ":" // rest(1:n))
      end if
    else if (text(1:3) == "use" .and. scan(text(4:4), " ,:") /= 0) then
      ! use x   use :: x   use, non_intrinsic :: x   (intrinsic ones are the compiler's)
      rest = adjustl(text(4:))
      colons = index(rest, "::")
      if (rest(1:1) == ",") then
        if (colons == 0) return
        if (index(rest(1:colons), "intrinsic") > 0 .and. index(rest(1:colons), "non_intrinsic") == 0) return
      end if
      if (colons > 0) rest = adjustl(rest(colons + 2:))
      n = name_length(rest)
      if (n > 0) call push(src%needs, rest(1:n))
    end if
  end subroutine statement

  ! index of the source that provides a name, 0 if none of this target's does
  integer function provider(name)
    character(len=*), intent(in) :: name
    integer :: i, k
    provider = 0
    do i = 1, size(sources)
      do k = 1, size(sources(i)%provides)
        if (sources(i)%provides(k)%s == name) then
          provider = i
          return
        end if
      end do
    end do
  end function provider

  subroutine check_duplicates()
    integer :: i, k, other
    do i = 1, size(sources)
      do k = 1, size(sources(i)%provides)
        other = provider(sources(i)%provides(k)%s)
        if (other /= i) call die("module '" // sources(i)%provides(k)%s // "' is defined by both " // &
                                 sources(other)%path // " and " // sources(i)%path)
      end do
    end do
  end subroutine check_duplicates

  ! depth-first: a source is emitted after the sources whose modules it needs
  recursive subroutine visit(i)
    integer, intent(in) :: i
    integer :: k, dependency
    if (sources(i)%state == 2) return
    if (sources(i)%state == 1) call die("modules depend on each other in a cycle through " // sources(i)%path)
    sources(i)%state = 1
    do k = 1, size(sources(i)%needs)
      dependency = provider(sources(i)%needs(k)%s)
      if (dependency /= 0 .and. dependency /= i) call visit(dependency)
    end do
    sources(i)%state = 2
    n_sorted = n_sorted + 1
    sorted(n_sorted) = i
  end subroutine visit

  function quoted(path) result(text)
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: text
    if (index(path, " ") > 0) then
      text = '"' // path // '"'
    else
      text = path
    end if
  end function quoted

end program module_order
