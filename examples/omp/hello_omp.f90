program hello_omp
    use omp_lib
    implicit none
    integer :: tid, nthreads

    !$omp parallel private(tid)
    tid = omp_get_thread_num()
    nthreads = omp_get_num_threads()
    print *, "thread", tid, "of", nthreads
    !$omp end parallel
end program hello_omp
