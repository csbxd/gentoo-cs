// SPDX-License-Identifier: GPL-2.0-only
// Fixed inputs and FP32 accumulation; also measure FP16-accum and FP32 controls.
#include <cuda_runtime.h>
#include <cuda_fp16.h>
#include <cuda_bf16.h>
#include <cublas_v2.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

static void check(cudaError_t s) {
    if (s != cudaSuccess) throw std::runtime_error(cudaGetErrorString(s));
}
static void check(cublasStatus_t s) {
    if (s != CUBLAS_STATUS_SUCCESS) throw std::runtime_error("cuBLAS status " + std::to_string(s));
}
__host__ __device__ static float value(uint32_t i, uint32_t seed) {
    return (int((i * 17u + i / 97u + seed * 13u) % 19u) - 9) / 32.0f;
}
template<class T> __device__ T cast(float x);
template<> __device__ float cast<float>(float x) { return x; }
template<> __device__ __half cast<__half>(float x) { return __float2half(x); }
template<> __device__ __nv_bfloat16 cast<__nv_bfloat16>(float x) { return __float2bfloat16(x); }
template<class T> __global__ void fill(T* p, uint32_t count, uint32_t seed) {
    for (uint32_t i = blockIdx.x * blockDim.x + threadIdx.x; i < count; i += blockDim.x * gridDim.x)
        p[i] = cast<T>(value(i, seed));
}
static void init(void* p, size_t count, cudaDataType t, unsigned seed) {
    if (t == CUDA_R_32F) fill<<<1024,256>>>((float*)p,count,seed);
    else if (t == CUDA_R_16F) fill<<<1024,256>>>((__half*)p,count,seed);
    else fill<<<1024,256>>>((__nv_bfloat16*)p,count,seed);
    check(cudaGetLastError());
}
struct Mode { const char* name; cudaDataType input, output; cublasComputeType_t compute; };
static void bench(cublasHandle_t handle, const Mode& m, int n, int trials, float batch_ms) {
    size_t count = size_t(n)*n;
    size_t isize = m.input == CUDA_R_32F ? 4 : 2, osize = m.output == CUDA_R_32F ? 4 : 2;
    void *a=nullptr,*b=nullptr,*c=nullptr;
    check(cudaMalloc(&a,count*isize)); check(cudaMalloc(&b,count*isize)); check(cudaMalloc(&c,count*osize));
    init(a,count,m.input,1); init(b,count,m.input,7); check(cudaMemset(c,0,count*osize));
    cublasMath_t math = m.compute == CUBLAS_COMPUTE_32F_PEDANTIC ? CUBLAS_PEDANTIC_MATH :
        (cublasMath_t)(CUBLAS_TENSOR_OP_MATH | CUBLAS_MATH_DISALLOW_REDUCED_PRECISION_REDUCTION);
    check(cublasSetMathMode(handle,math));
    float alpha=1,beta=0; __half ah=__float2half(1),bh=__float2half(0);
    bool half_accum = m.compute == CUBLAS_COMPUTE_16F;
    auto gemm=[&]() {
        check(cublasGemmEx(handle,CUBLAS_OP_N,CUBLAS_OP_N,n,n,n,
            half_accum?(void*)&ah:(void*)&alpha,a,m.input,n,b,m.input,n,
            half_accum?(void*)&bh:(void*)&beta,c,m.output,n,m.compute,CUBLAS_GEMM_DEFAULT));
    };
    auto start=std::chrono::steady_clock::now();
    do { gemm(); check(cudaDeviceSynchronize()); }
    while (std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count()<1.0);
    cudaEvent_t begin,end; check(cudaEventCreate(&begin));check(cudaEventCreate(&end));
    auto timed=[&](int iterations) {
        check(cudaEventRecord(begin));for(int i=0;i<iterations;++i)gemm();
        check(cudaEventRecord(end));check(cudaEventSynchronize(end));
        float ms;check(cudaEventElapsedTime(&ms,begin,end));return ms/iterations;
    };
    float estimate=timed(3);int iterations=std::max(1,int(std::ceil(batch_ms/estimate)));
    std::vector<float> times;
    for(int i=0;i<trials;++i)times.push_back(timed(iterations));
    std::vector<float> sorted=times;std::sort(sorted.begin(),sorted.end());
    double median=sorted[sorted.size()/2];
    std::vector<float> out(count);
    if(m.output==CUDA_R_32F)check(cudaMemcpy(out.data(),c,count*4,cudaMemcpyDeviceToHost));
    else {
        std::vector<__half> raw(count);check(cudaMemcpy(raw.data(),c,count*2,cudaMemcpyDeviceToHost));
        for(size_t i=0;i<count;++i)out[i]=__half2float(raw[i]);
    }
    uint64_t digest=14695981039346656037ull;double max_error=0;bool valid=true;
    for(float x:out) {
        uint32_t bits;std::memcpy(&bits,&x,4);digest^=bits;digest*=1099511628211ull;
        if(!std::isfinite(x))valid=false;
    }
    for(unsigned i=0;i<64;++i) {
        unsigned row=(i*127u+13)%n,col=(i*251u+31)%n;double expected=0;
        for(int k=0;k<n;++k)expected+=double(value(row+uint32_t(k)*n,1))*value(k+uint32_t(col)*n,7);
        double err=std::abs(out[row+size_t(col)*n]-expected);max_error=std::max(max_error,err);
        if(err>(half_accum?1.0+0.02*std::abs(expected):0.001))valid=false;
    }
    std::printf("{\"mode\":\"%s\",\"n\":%d,\"trials\":%d,\"iterations_per_trial\":%d,\"median_ms\":%.6f,\"tflops\":%.6f,\"max_sample_abs_error\":%.8f,\"correct\":%s,\"output_hash\":\"%016llx\",\"samples_ms\":[",
        m.name,n,trials,iterations,median,2.0*n*n*n/(median*1e9),max_error,valid?"true":"false",(unsigned long long)digest);
    for(size_t i=0;i<times.size();++i)std::printf("%s%.6f",i?",":"",times[i]);
    std::puts("]}");std::fflush(stdout);
    check(cudaEventDestroy(begin));check(cudaEventDestroy(end));
    check(cudaFree(a));check(cudaFree(b));check(cudaFree(c));
    if(!valid)throw std::runtime_error("numerical verification failed");
}
int main(int argc,char** argv) {
    try {
        int trials=7;float batch_ms=400;
        if(argc>1)trials=std::stoi(argv[1]);if(argc>2)batch_ms=std::stof(argv[2]);
        if(trials<1||trials>31||batch_ms<10||batch_ms>5000)throw std::runtime_error("invalid timing parameters");
        cublasHandle_t handle;check(cublasCreate(&handle));check(cublasSetAtomicsMode(handle,CUBLAS_ATOMICS_NOT_ALLOWED));
        const Mode modes[]={
            {"fp16_fp32",CUDA_R_16F,CUDA_R_32F,CUBLAS_COMPUTE_32F},
            {"bf16_fp32",CUDA_R_16BF,CUDA_R_32F,CUBLAS_COMPUTE_32F},
            {"tf32_fp32",CUDA_R_32F,CUDA_R_32F,CUBLAS_COMPUTE_32F_FAST_TF32},
            {"fp16_fp16_control",CUDA_R_16F,CUDA_R_16F,CUBLAS_COMPUTE_16F},
            {"fp32_control",CUDA_R_32F,CUDA_R_32F,CUBLAS_COMPUTE_32F_PEDANTIC}
        };
        for(const auto& mode:modes)for(int n:{4096,8192})bench(handle,mode,n,trials,batch_ms);
        check(cublasDestroy(handle));return 0;
    } catch(const std::exception& e) {std::fprintf(stderr,"tensor-bench: %s\n",e.what());return 1;}
}
