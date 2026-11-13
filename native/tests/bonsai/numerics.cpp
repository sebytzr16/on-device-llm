#include "ggml.h"
#include "ggml-cpu.h"
#include "ggml-backend.h"
#include "ggml-alloc.h"
#include "ggml-quants.h"
#include "ggml-cpu/quants.h"
#include "gguf.h"
#ifdef BONSAI_CUDA
#include "ggml-cuda.h"
#endif
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <map>
#include <vector>

static void require(bool ok, const char * what) {
    if (!ok) { std::fprintf(stderr, "FAIL: %s\n", what); std::exit(1); }
}

// Independent base-3 byte decoder: high trit first, wrapped byte per digit.
static int trit(unsigned byte, int digit) {
    for (int i = 0; i < digit; ++i) { byte = (byte * 3) % 256; }
    return int(byte * 3 / 256) - 1;
}

static void scalar_tests() {
    ggml_cpu_init();
    auto * init = ggml_init({1024*1024, nullptr, false}); // initialize fp16 tables
    size_t values = 0;
    for (unsigned byte = 0; byte < 256; ++byte) {
        block_ptq1_0 pt{}; block_pq2_0 pq{};
        pt.d = pq.d = ggml_fp32_to_fp16(0.125f);
        std::memset(pt.qs, byte, sizeof(pt.qs));
        std::memset(pt.qh, byte, sizeof(pt.qh));
        std::memset(pq.qs, byte, sizeof(pq.qs));
        float p[128], q[128];
        dequantize_row_ptq1_0(&pt, p, 128);
        dequantize_row_pq2_0(&pq, q, 128);
        for (int e = 0; e < 128; ++e) {
            int digit = e < 80 ? e / 16 : e < 120 ? (e - 80) / 8 : (e - 120) / 2;
            require(p[e] == 0.125f * trit(byte, digit), "PTQ exhaustive byte decode");
            require(q[e] == 0.125f * (int((byte >> (2*(e%4))) & 3) - 1), "PQ exhaustive byte decode");
            values += 2;
        }
    }
    std::mt19937 rng(43);
    float max_error = 0;
    for (int it = 0; it < 1000; ++it) {
        block_ptq1_0 pt[4]; block_pq2_0 pq[4]; block_q8_0 y[16];
        for (int b = 0; b < 4; ++b) {
            for (auto & v : pt[b].qs) v = uint8_t(rng());
            for (auto & v : pt[b].qh) v = uint8_t(rng());
            for (auto & v : pq[b].qs) v = uint8_t(rng());
            pt[b].d = pq[b].d = ggml_fp32_to_fp16(float(b+1)/32);
        }
        for (auto & b : y) {
            b.d = ggml_fp32_to_fp16(0.0625f);
            for (auto & v : b.qs) v = int8_t(int(rng()%255)-127);
        }
        float x[512], fy[512], got;
        dequantize_row_q8_0(y, fy, 512);
        for (int type = 0; type < 2; ++type) {
            if (type) { dequantize_row_ptq1_0(pt,x,512); ggml_vec_dot_ptq1_0_q8_0(512,&got,0,pt,0,y,0,1); }
            else { dequantize_row_pq2_0(pq,x,512); ggml_vec_dot_pq2_0_q8_0(512,&got,0,pq,0,y,0,1); }
            for (int e=0;e<512;++e) {
                int b=e/128, j=e%128;
                int digit=j<80 ? j/16 : j<120 ? (j-80)/8 : (j-120)/2;
                unsigned byte=j<80 ? pt[b].qs[j%16] : j<120 ? pt[b].qs[16+(j-80)%8] : pt[b].qh[(j-120)%2];
                float ref = type ? trit(byte,digit) * ggml_fp16_to_fp32(pt[b].d)
                                 : (int((pq[b].qs[j/4] >> (2*(j%4))) & 3)-1) * ggml_fp16_to_fp32(pq[b].d);
                require(x[e]==ref,"random distinct-byte ordering");
            }
            double expected = 0; for (int e=0;e<512;++e) expected += double(x[e])*fy[e];
            max_error = std::max(max_error, float(std::abs(got-expected)));
            if (std::abs(got-expected)>=1e-5) std::fprintf(stderr,"type=%d it=%d got=%.9g expected=%.9g\n",type,it,got,expected);
            require(std::abs(got-expected)<1e-5,"scalar Q8 dot");
        }
    }
    std::printf("scalar: %zu exhaustive decoded values, 2000 dot products, max_abs_error=%.9g\n", values, max_error);
    for (int t = 44; t < 142; ++t) {
        require(ggml_blck_size(ggml_type(t)) == 0, "reserved block size");
        require(std::strcmp(ggml_type_name(ggml_type(t)), "UNKNOWN") == 0, "reserved type name");
    }
    unsigned char dummy[128] = {};
    require(!ggml_validate_row_data(ggml_type(44), dummy, sizeof(dummy)), "reserved type rejected without division by zero");
    // Minimal valid GGUF envelope with one tensor, but a reserved type id.
    std::vector<unsigned char> gguf;
    auto append = [&](uint64_t v,int bytes) { for(int i=0;i<bytes;++i) gguf.push_back((v>>(8*i))&255); };
    append(0x46554747,4); append(3,4); append(1,8); append(0,8);
    append(1,8); append('x',1); append(1,4); append(128,8); append(44,4); append(0,8);
    while(gguf.size()%32) gguf.push_back(0);
    gguf.resize(gguf.size()+128);
    require(gguf_init_from_buffer(gguf.data(),gguf.size(),{true,nullptr})==nullptr,"GGUF reserved type rejected");
    ggml_free(init);
}

static void graph_tests(ggml_backend_t backend) {
    static std::map<std::pair<ggml_type,int>,std::vector<float>> cpu_outputs;
    constexpr int k=512, rows=32;
    std::mt19937 rng(44);
    for (auto type : {GGML_TYPE_PQ2_0, GGML_TYPE_PTQ1_0, GGML_TYPE_Q4_K, GGML_TYPE_Q8_0, GGML_TYPE_IQ4_NL}) {
        std::vector<uint8_t> packed(ggml_row_size(type,k)*rows);
        std::vector<float> weights(k*rows), decoded(k*rows);
        for (auto & v : weights) v = float(int(rng()%201)-100)/64;
        if (type == GGML_TYPE_PQ2_0 || type == GGML_TYPE_PTQ1_0) {
            for (auto & v : packed) v = uint8_t(rng());
            for (int b=0;b<k*rows/128;++b) {
                auto d = ggml_fp32_to_fp16(float(b%4+1)/32);
                if (type == GGML_TYPE_PQ2_0) reinterpret_cast<block_pq2_0 *>(packed.data())[b].d=d;
                else reinterpret_cast<block_ptq1_0 *>(packed.data())[b].d=d;
            }
        } else {
            require(ggml_quantize_chunk(type,weights.data(),packed.data(),0,rows,k,nullptr)==packed.size(),"quantize regression tensor");
        }
        ggml_get_type_traits(type)->to_float(packed.data(),decoded.data(),k*rows);
        for (int batch : {1,4,16}) {
            auto * ctx=ggml_init({4*1024*1024,nullptr,true});
            auto * a=ggml_new_tensor_2d(ctx,type,k,rows);
            auto * b=ggml_new_tensor_2d(ctx,GGML_TYPE_F32,k,batch);
            auto * mm=ggml_mul_mat(ctx,a,b);
            auto * ids=ggml_new_tensor_1d(ctx,GGML_TYPE_I32,rows);
            auto * get=ggml_get_rows(ctx,a,ids);
            auto * graph=ggml_new_graph(ctx);
            ggml_build_forward_expand(graph,mm); ggml_build_forward_expand(graph,get);
            require(ggml_backend_supports_op(backend,mm),"backend supports matmul");
            require(ggml_backend_supports_op(backend,get),"backend supports get_rows");
            auto buf=ggml_backend_alloc_ctx_tensors(ctx,backend);
            require(buf!=nullptr,"graph allocation");
            ggml_backend_buffer_set_usage(buf,GGML_BACKEND_BUFFER_USAGE_WEIGHTS);
            std::vector<float> input(k*batch),output(rows*batch),readback(k*rows);
            for (auto & v : input) v=float(int(rng()%201)-100)/64;
            std::vector<int> indices(rows); for(int r=0;r<rows;++r) indices[r]=r;
            ggml_backend_tensor_set(a,packed.data(),0,packed.size());
            ggml_backend_tensor_set(b,input.data(),0,input.size()*sizeof(float));
            ggml_backend_tensor_set(ids,indices.data(),0,indices.size()*sizeof(int));
            require(ggml_backend_graph_compute(backend,graph)==GGML_STATUS_SUCCESS,"graph compute");
            ggml_backend_tensor_get(mm,output.data(),0,output.size()*sizeof(float));
            ggml_backend_tensor_get(get,readback.data(),0,readback.size()*sizeof(float));
            require(readback==decoded,"get_rows bit exact dequant");
            double err=0,norm=0;
            for(int c=0;c<batch;++c) for(int r=0;r<rows;++r) {
                double ref=0; for(int e=0;e<k;++e) ref+=double(decoded[r*k+e])*input[c*k+e];
                err+=std::pow(output[c*rows+r]-ref,2); norm+=ref*ref;
            }
            double nrmse=std::sqrt(err/std::max(norm,1e-30));
            std::printf("%s %s batch=%d get_rows=exact matmul_nrmse=%.8f\n",ggml_backend_name(backend),ggml_type_name(type),batch,nrmse);
            require(nrmse<0.02,"matmul vs float64 reference");
            if (std::strcmp(ggml_backend_name(backend),"CPU")==0) {
                cpu_outputs[{type,batch}]=output;
            } else if ((type==GGML_TYPE_PQ2_0 || type==GGML_TYPE_PTQ1_0) && batch<=4) {
                const auto & ref=cpu_outputs.at({type,batch});
                float max_abs=0; for(size_t i=0;i<ref.size();++i) max_abs=std::max(max_abs,std::abs(ref[i]-output[i]));
                std::printf("CPU/CUDA %s batch=%d max_abs_diff=%.9g\n",ggml_type_name(type),batch,max_abs);
                require(max_abs<1e-5,"CPU/CUDA ternary matvec agreement");
            }
            ggml_backend_buffer_free(buf); ggml_free(ctx);
        }
    }
}

int main(int argc,char **argv) {
    scalar_tests();
    auto cpu=ggml_backend_cpu_init(); ggml_backend_cpu_set_n_threads(cpu,4);
    graph_tests(cpu); ggml_backend_free(cpu);
#ifdef BONSAI_CUDA
    if(argc>1 && std::strcmp(argv[1],"--cuda")==0) {
        auto cuda=ggml_backend_cuda_init(0); require(cuda!=nullptr,"CUDA init");
        graph_tests(cuda); ggml_backend_free(cuda);
    }
#endif
    std::puts("PASS");
}
