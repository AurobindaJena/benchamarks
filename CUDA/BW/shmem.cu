#include <cstdio>
#include <cassert>
#include <cstdlib>
#include "rtc.h"
#include "cudamem.h"

#define __out

#ifdef FP64
typedef double real;
#else
typedef float real;
#endif

#define WARP_SIZE2 5

dim3 grid(const int nt, const int n)
{
  const int nb = (n-1)/nt + 1;
  dim3 grid(nb);
  if (grid.x > 65535)
  {
    grid.x = std::sqrt(nb);
    grid.y = (nb-1)/grid.x + 1;
  }
  return grid;
}

template<int M, int MODE>
__global__ void dev_compute(
    const int   n,
    const real *in,
    __out real *out)
{
  const int bid = blockIdx.y*gridDim.x + blockIdx.x;
  const int tid = bid * blockDim.x + threadIdx.x;
  
  real res = real(0.0);

  const int t0 = ((tid >> WARP_SIZE2) << WARP_SIZE2) >> 1;
  if (MODE == 0)
  {

    real xd[M];
#pragma unroll
    for (int i = 0; i < M; i++)
      xd[i] = in[t0+i];

#pragma unroll
    for (int i = 0; i < M; i++)
    {
#pragma unroll
      for (int j = 0; j < M; j++)
        res += xd[j]*xd[i];
    }

  }
  else
  {
    volatile __shared__ real sxd[M];
    if (tid < M)
      sxd[tid] = in[t0+tid];
    __syncthreads();

    if (MODE == 1)
    {

      real xd[M];
#pragma unroll
      for (int i = 0; i < M; i++)
        xd[i] = in[t0+i];

#pragma unroll
      for (int i = 0; i < M; i++)
      {
#pragma unroll
        for (int j = 0; j < M; j++)
          res += xd[j]*sxd[i];
      }

    }
    else
    {

#pragma unroll
      for (int i = 0; i < M; i++)
      {
#pragma unroll
        for (int j = 0; j < M; j++)
          res += sxd[j]*sxd[i];
      }

    }
  }

  /* unlikely it will ever write result to RAM */
  if (res == real(123.123456) && tid < n)
    out[tid] = res;

}

int main(int argc, char * argv[])
{
  const size_t nMel = argc > 1 ? atoi(argv[1]) : 1;
  cuda_mem<real> d_in, d_out;
  host_mem<real> h_data;

  fprintf(stderr, " testing BW on %llu Melements\n", (unsigned long long)nMel);

  const size_t n = nMel * 1000000;

  h_data.realloc(n);
  d_in  .realloc(n);
  d_out .realloc(n);

#ifdef FP64
  const int M = 16;
#else
  const int M = 32;
#endif
  {
    fprintf(stderr, " compute  REG - REG : ");
    const real   f = (real)argc;
    for (size_t i = 0; i < n; i++)
      h_data[i] = f;
    d_in.h2d(h_data);

    const double t0 = rtc();
    const int NTHREADS = 256;
    dev_compute<M,0><<<grid(NTHREADS,n), NTHREADS>>>(n, d_in, d_out);
    CUDA_SAFE_CALL(cudaThreadSynchronize());
    const double dt =  rtc() - t0;
    fprintf(stderr, " %g GFLOP/s\n", n*M*M*2/dt/1e9);
  }
  {
    fprintf(stderr, " compute SHMEM- REG : ");
    const real   f = (real)argc;
    for (size_t i = 0; i < n; i++)
      h_data[i] = f;
    d_in.h2d(h_data);

    const double t0 = rtc();
    const int NTHREADS = 256;
    dev_compute<M,1><<<grid(NTHREADS,n), NTHREADS>>>(n, d_in, d_out);
    CUDA_SAFE_CALL(cudaThreadSynchronize());
    const double dt =  rtc() - t0;
    fprintf(stderr, " %g GFLOP/s\n", n*M*M*2/dt/1e9);
  }
  {
    fprintf(stderr, " compute SHMEM-SHMEM: ");
    const real   f = (real)argc;
    for (size_t i = 0; i < n; i++)
      h_data[i] = f;
    d_in.h2d(h_data);

    const double t0 = rtc();
    const int NTHREADS = 256;
    dev_compute<M,2><<<grid(NTHREADS,n), NTHREADS>>>(n, d_in, d_out);
    CUDA_SAFE_CALL(cudaThreadSynchronize());
    const double dt =  rtc() - t0;
    fprintf(stderr, " %g GFLOP/s\n", n*M*M*2/dt/1e9);
  }


  return 0;
}


