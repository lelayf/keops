
#include <stdio.h>
#include <iostream>
#include <assert.h>
#include <cuda.h>

#include "Pack.h"

using namespace std;


template <typename T>
__device__ static constexpr T static_max_device(T a, T b) {
    return a < b ? b : a;
}

template <typename TYPE, int DIMVECT>
__global__ void reduce0(TYPE* in, TYPE* out, int sizeY,int nx) {
    /* Function used as a final reduction pass in the 2D scheme,
     * once the block reductions have been made.
     * Takes as input:
     * - in,  a  sizeY * (nx * DIMVECT ) array
     * - out, an          nx * DIMVECT   array
     *
     * Computes, in parallel, the "columnwise"-sum (which correspond to lines of blocks)
     * of *in and stores the result in out.
     */
    TYPE res = 0;
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if(tid < nx*DIMVECT) {
        for (int i = 0; i < sizeY; i++)
            res += in[tid + i*nx*DIMVECT]; // We use "+=" as a reduction op. But it could be anything, really!
        /*res = in[tid+ nx* DIMVECT];*/
        out[tid] = res;
    }
}








// thread kernel: computation of x1i = sum_j k(x2i,x3i,...,y1j,y2j,...) for index i given by thread id.
// N.B.: This routine by itself is generic, and does not specifically refer to the "sum" operation.
//       It can be used for any Map-Reduce operation, provided that "fun" is well-understood.
template < typename TYPE, class FUN, class PARAM >
__global__ void GpuConv2DOnDevice(FUN fun, PARAM param, int nx, int ny, TYPE** px, TYPE** py) {
    /*
     * px and py are pointers to the device global memory.
     * both are arrays of arrays with the relevant size: for instance,
     * px[1] is a TYPE array of size ( nx * DIMSX::VAL(1) ).
     *
     * (*px) = px[0] is the output array, of size (nx * DIMSX::FIRST).
     *
     */
    // gets dimensions and number of variables of inputs of function FUN
    using DIMSX = typename FUN::DIMSX;  // DIMSX is a "vector" of templates giving dimensions of xi variables
    using DIMSY = typename FUN::DIMSY;  // DIMSY is a "vector" of templates giving dimensions of yj variables
    const int DIMPARAM = FUN::DIMPARAM; // DIMPARAM is the total size of the param vector
    const int DIMX = DIMSX::SUM;        // DIMX  is sum of dimensions for xi variables
    const int DIMY = DIMSY::SUM;        // DIMY  is sum of dimensions for yj variables
    const int DIMX1 = DIMSX::FIRST;     // DIMX1 is dimension of output variable

    // Load the parameter vector in the Thread Memory, for improved efficiency
    //TYPE param_loc[static_max_device(DIMPARAM,1)];
    // (Jean :) Direct inlining to compile on Ubuntu 16.04 with nvcc7.5,
    //          which is a standard config in research. For whatever reason, I can't make
    //          it work an other way... Is it bad practice/performance?
    TYPE param_loc[DIMPARAM < 1 ? 1 : DIMPARAM];

    for(int k=0; k<DIMPARAM; k++)
        param_loc[k] = param[k];

    // Weird syntax to create a pointer in shared memory.
    extern __shared__ char yj_char[];
    TYPE* const yj = reinterpret_cast<TYPE*>(yj_char);

    // Step 1 : Load in Thread Memory the information needed in the current line ---------------------------
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    TYPE xi[DIMX];
    TYPE tmp[DIMX1];
    if(i<nx) { // we will compute x1i only if i is in the range
        for(int k=0; k<DIMX1; k++)
            tmp[k] = 0.0f; // initialize output
        // Load xi from device global memory.
        // Remember that we use an interleaved memory scheme where
        // xi = [ x1i, x2i, x3i, ... ].
        // Since we do not want to erase x1i, and only load x2i, x3i, etc.,
        // we add a small offset to the pointer given as an argument to the loading routine,
        // and ask it to only load "DIMSX::NEXT" bits of memory.
        load<DIMSX::NEXT>(i,xi+DIMX1,px+1); // load xi variables from global memory to local thread memory
    }

    // Step 2 : Load in Shared Memory the information needed in the current block of the product -----------
    // In the 1D scheme, we use a loop to run through the line.
    // In the 2D scheme presented here, the computation is done in parallel wrt both lines and columns.
    // Hence, we use "blockId.y" to get our current column number.
    int j = blockIdx.y * blockDim.x + threadIdx.x; // Same blockDim in x and y : squared tiles.
    if(j<ny) // we load yj from device global memory only if j<ny
        load<DIMSY>(j,yj+threadIdx.x*DIMY,py); // load yj variables from global memory to shared memory
    // More precisely : the j-th line of py is loaded to yj, at a location which depends on the
    // current threadId.

    __syncthreads(); // Make sure nobody lags behind

    // Step 3 : Once the data is loaded, execute fun --------------------------------------------------------
    // N.B.: There's no explicit summation here. Just calls to fun, which *accumulates* the results
    //       along the line, but does not *have* to use a "+=" as reduction operator.
    //       In the future, we could provide other reductions: max, min, ... whatever's needed.

    if(i<nx) { // we compute x1i only if needed
        TYPE* yjrel = yj; // Loop on the columns of the current block.
        for(int jrel = 0; (jrel<blockDim.x) && ((blockDim.x*blockIdx.y+jrel)< ny); jrel++, yjrel+=DIMY) {
            call<DIMSX,DIMSY>(fun,xi,yjrel,param_loc); // Call the function, which accumulates results in xi[0:DIMX1]
            for(int k=0; k<DIMX1; k++)
                tmp[k] += xi[k];
        }
    }
    __syncthreads();

    // Step 4 : Save the result in global memory -----------------------------------------------------------
    // The current thread has computed the "linewise-sum" of a small block of the full Kernel Product
    // matrix, which corresponds to KP[ blockIdx.x * blockDim.x : (blockIdx.x+1) * blockDim.x ,
    //                                  blockIdx.y * blockDim.x : (blockIdx.y+1) * blockDim.x ]
    // We accumulate it in the output array (*px) = px[0], which has in fact gridSize.y * nx
    // lines of size DIMX1. The final reduction, which "sums over the block lines",
    // shall be done in a later step.
    if(i<nx)
        for(int k=0; k<DIMX1; k++)
            (*px)[blockIdx.y*DIMX1*nx+i*DIMX1+k] = tmp[k];
}
///////////////////////////////////////////////////


template < typename TYPE, class FUN, class PARAM >
int GpuConv2D_FromHost(FUN fun, PARAM param_h, int nx, int ny, TYPE** px_h, TYPE** py_h) {

    using DIMSX = typename FUN::DIMSX;
    using DIMSY = typename FUN::DIMSY;
    const int DIMPARAM = FUN::DIMPARAM;
    const int DIMX = DIMSX::SUM;
    const int DIMY = DIMSY::SUM;
    const int DIMX1 = DIMSX::FIRST;
    const int SIZEI = DIMSX::SIZE;
    const int SIZEJ = DIMSY::SIZE;

    // Compute on device : grid is 2d and block is 1d
    dim3 blockSize;
    blockSize.x = 192; // number of threads in each block
    dim3 gridSize;
    gridSize.x =  nx / blockSize.x + (nx%blockSize.x==0 ? 0 : 1);
    gridSize.y =  ny / blockSize.x + (ny%blockSize.x==0 ? 0 : 1);

    // Reduce  : grid and block are both 1d
    dim3 blockSize2;
    blockSize2.x = 192; // number of threads in each block
    dim3 gridSize2;
    gridSize2.x =  (nx*DIMX1) / blockSize2.x + ((nx*DIMX1)%blockSize2.x==0 ? 0 : 1);


    // Data on the device. We need an "inflated" x1B, which contains gridSize.y "copies" of x_d
    // that will be reduced in the final pass.
    TYPE *x1B, *x_d, *y_d, *param_d;

    // device arrays of pointers to device data
    TYPE **px_d, **py_d;

    // single cudaMalloc
    void **p_data;
    cudaMalloc((void**)&p_data, sizeof(TYPE*)*(SIZEI+SIZEJ)+sizeof(TYPE)*(DIMPARAM+nx*DIMX+ny*DIMY+nx*DIMX1*gridSize.y));

    TYPE **p_data_a = (TYPE**)p_data;
    px_d = p_data_a;
    p_data_a += SIZEI;
    py_d = p_data_a;
    p_data_a += SIZEJ;
    TYPE *p_data_b = (TYPE*)p_data_a;
    param_d = p_data_b;
    p_data_b += DIMPARAM;
    x_d = p_data_b;
    p_data_b += nx*DIMX;
    y_d = p_data_b;
    p_data_b += ny*DIMY;
    x1B = p_data_b;

    // host arrays of pointers to device data
    TYPE *phx_d[SIZEI];
    TYPE *phy_d[SIZEJ];

    // Send data from host to device.
    cudaMemcpy(param_d, param_h, sizeof(TYPE)*DIMPARAM, cudaMemcpyHostToDevice);

    int nvals;
    phx_d[0] = x_d;
    nvals = nx*DIMSX::VAL(0);
    for(int k=1; k<SIZEI; k++) {
        phx_d[k] = phx_d[k-1] + nvals;
        nvals = nx*DIMSX::VAL(k);
        cudaMemcpy(phx_d[k], px_h[k], sizeof(TYPE)*nvals, cudaMemcpyHostToDevice);
    }
    phy_d[0] = y_d;
    nvals = ny*DIMSY::VAL(0);
    cudaMemcpy(phy_d[0], py_h[0], sizeof(TYPE)*nvals, cudaMemcpyHostToDevice);
    for(int k=1; k<SIZEJ; k++) {
        phy_d[k] = phy_d[k-1] + nvals;
        nvals = ny*DIMSY::VAL(k);
        cudaMemcpy(phy_d[k], py_h[k], sizeof(TYPE)*nvals, cudaMemcpyHostToDevice);
    }

    phx_d[0] = x1B; // we write the result before reduction in the "inflated" vector

    // copy arrays of pointers
    cudaMemcpy(px_d, phx_d, SIZEI*sizeof(TYPE*), cudaMemcpyHostToDevice);
    cudaMemcpy(py_d, phy_d, SIZEJ*sizeof(TYPE*), cudaMemcpyHostToDevice);

    // Size of the SharedData : blockSize.x*(DIMY)*sizeof(TYPE)
    GpuConv2DOnDevice<TYPE><<<gridSize,blockSize,blockSize.x*(DIMY)*sizeof(TYPE)>>>(fun,param_d,nx,ny,px_d,py_d);

    // Since we've used a 2D scheme, there's still a "blockwise" line reduction to make on
    // the output array px_d[0] = x1B. We go from shape ( gridSize.y * nx, DIMX1 ) to (nx, DIMX1)
    reduce0<TYPE,DIMX1><<<gridSize2, blockSize2>>>(x1B, x_d, gridSize.y,nx);

    // block until the device has completed
    cudaThreadSynchronize();

    // Send data from device to host.
    cudaMemcpy(*px_h, x_d, sizeof(TYPE)*(nx*DIMX1),cudaMemcpyDeviceToHost);

    // Free memory.
    cudaFree(p_data);

    return 0;
}



template < typename TYPE, class FUN, class PARAM >
int GpuConv2D_FromDevice(FUN fun, PARAM param_d, int nx, int ny, TYPE** px_d, TYPE** py_d) {

    typedef typename FUN::DIMSX DIMSX;
    typedef typename FUN::DIMSY DIMSY;
    const int DIMY = DIMSY::SUM;
    const int DIMX1 = DIMSX::FIRST;

    // Data on the device. We need an "inflated" x1B, which contains gridSize.y "copies" of x_d
    // that will be reduced in the final pass.
    TYPE *x1B, *out;

    // Compute on device : grid is 2d and block is 1d
    dim3 blockSize;
    blockSize.x = 192; // number of threads in each block
    dim3 gridSize;
    gridSize.x =  nx / blockSize.x + (nx%blockSize.x==0 ? 0 : 1);
    gridSize.y =  ny / blockSize.x + (ny%blockSize.x==0 ? 0 : 1);

    // Reduce : grid and block are both 1d
    dim3 blockSize2;
    blockSize2.x = 192; // number of threads in each block
    dim3 gridSize2;
    gridSize2.x =  (nx*DIMX1) / blockSize2.x + ((nx*DIMX1)%blockSize2.x==0 ? 0 : 1);

    cudaMalloc((void**)&x1B, sizeof(TYPE)*(nx*DIMX1*gridSize.y));
    out = px_d[0]; // save the output location
    px_d[0] = x1B;

    // Size of the SharedData : blockSize.x*(DIMY)*sizeof(TYPE)
    GpuConv2DOnDevice<TYPE><<<gridSize,blockSize,blockSize.x*(DIMY)*sizeof(TYPE)>>>(fun,param_d,nx,ny,px_d,py_d);

    // Since we've used a 2D scheme, there's still a "blockwise" line reduction to make on
    // the output array px_d[0] = x1B. We go from shape ( gridSize.y * nx, DIMX1 ) to (nx, DIMX1)
    reduce0<TYPE,DIMX1><<<gridSize2, blockSize2>>>(x1B, out, gridSize.y,nx);

    // block until the device has completed
    cudaThreadSynchronize();

    return 0;
}


// Wrapper around GpuConv2D, which takes lists of arrays *x1, *x2, ..., *y1, *y2, ...
// and use getlist to enroll them into "pointers arrays" px and py.
template < typename TYPE, class FUN, class PARAM, typename... Args >
int GpuConv2D(FUN fun, PARAM param, int nx, int ny, TYPE* x1_h, Args... args) {

    typedef typename FUN::VARSI VARSI;
    typedef typename FUN::VARSJ VARSJ;

    const int SIZEI = VARSI::SIZE+1;
    const int SIZEJ = VARSJ::SIZE;

    using DIMSX = GetDims<VARSI>;
    using DIMSY = GetDims<VARSJ>;

    using INDSI = GetInds<VARSI>;
    using INDSJ = GetInds<VARSJ>;

    TYPE *px_h[SIZEI];
    TYPE *py_h[SIZEJ];

    px_h[0] = x1_h;
    getlist<INDSI>(px_h+1,args...);
    getlist<INDSJ>(py_h,args...);

    return GpuConv2D_FromHost(fun,param,nx,ny,px_h,py_h);

}

// Idem, but with args given as an array of arrays, instead of an explicit list of arrays
template < typename TYPE, class FUN, class PARAM >
int GpuConv2D(FUN fun, PARAM param, int nx, int ny, TYPE* x1_h, TYPE** args) {
    typedef typename FUN::VARSI VARSI;
    typedef typename FUN::VARSJ VARSJ;

    const int SIZEI = VARSI::SIZE+1;
    const int SIZEJ = VARSJ::SIZE;

    using DIMSX = GetDims<VARSI>;
    using DIMSY = GetDims<VARSJ>;

    using INDSI = GetInds<VARSI>;
    using INDSJ = GetInds<VARSJ>;

    TYPE *px_h[SIZEI];
    TYPE *py_h[SIZEJ];

    px_h[0] = x1_h;
    for(int i=1; i<SIZEI; i++)
        px_h[i] = args[INDSI::VAL(i-1)];
    for(int i=0; i<SIZEJ; i++)
        py_h[i] = args[INDSJ::VAL(i)];
        
    return GpuConv2D_FromHost(fun,param,nx,ny,px_h,py_h);

}


// Same wrappers, but for data located on the device
template < typename TYPE, class FUN, class PARAM, typename... Args >
int GpuConv2D_FromDevice(FUN fun, PARAM param, int nx, int ny, TYPE* x1_d, Args... args) {

    typedef typename FUN::VARSI VARSI;
    typedef typename FUN::VARSJ VARSJ;

    const int SIZEI = VARSI::SIZE+1;
    const int SIZEJ = VARSJ::SIZE;

    using DIMSX = GetDims<VARSI>;
    using DIMSY = GetDims<VARSJ>;

    using INDSI = GetInds<VARSI>;
    using INDSJ = GetInds<VARSJ>;

    TYPE *px_d[SIZEI];
    TYPE *py_d[SIZEJ];

    px_d[0] = x1_d;
    getlist<INDSI>(px_d+1,args...);
    getlist<INDSJ>(py_d,args...);

    return GpuConv2D_FromDevice(fun,param,nx,ny,px_d,py_d);

}

template < typename TYPE, class FUN, class PARAM >
int GpuConv2D_FromDevice(FUN fun, PARAM param, int nx, int ny, TYPE* x1_d, TYPE** args) {
    typedef typename FUN::VARSI VARSI;
    typedef typename FUN::VARSJ VARSJ;

    const int SIZEI = VARSI::SIZE+1;
    const int SIZEJ = VARSJ::SIZE;

    using DIMSX = GetDims<VARSI>;
    using DIMSY = GetDims<VARSJ>;

    using INDSI = GetInds<VARSI>;
    using INDSJ = GetInds<VARSJ>;

    TYPE *px_d[SIZEI];
    TYPE *py_d[SIZEJ];

    px_d[0] = x1_d;
    for(int i=1; i<SIZEI; i++)
        px_d[i] = args[INDSI::VAL(i-1)];
    for(int i=0; i<SIZEJ; i++)
        py_d[i] = args[INDSJ::VAL(i)];

    return GpuConv2D_FromDevice(fun,param,nx,ny,px_d,py_d);

}




