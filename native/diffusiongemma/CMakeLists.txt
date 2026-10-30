cmake_minimum_required(VERSION 3.20)
project(dg_host LANGUAGES CXX)
# Build the PR first with the same compiler/configuration. Import only its
# libraries; never link this runtime into the Flutter bridge.
set(DG_SOURCE "" CACHE PATH "Diffusion llama.cpp checkout")
set(DG_BUILD "" CACHE PATH "Built diffusion llama.cpp tree")
add_executable(dg_host dg_host.cpp)
target_compile_features(dg_host PRIVATE cxx_std_17)
target_compile_definitions(dg_host PRIVATE LLAMA_SHARED GGML_SHARED LLAMA_COMMON_SHARED)
target_include_directories(dg_host PRIVATE
  "${DG_SOURCE}/include" "${DG_SOURCE}/ggml/include"
  "${DG_SOURCE}/common" "${DG_SOURCE}/vendor"
  "${DG_SOURCE}/examples/diffusion")
target_link_libraries(dg_host PRIVATE
  "${DG_BUILD}/examples/diffusion/llama-diffusion.lib"
  "${DG_BUILD}/common/llama-common.lib"
  "${DG_BUILD}/src/llama.lib"
  "${DG_BUILD}/ggml/src/ggml.lib"
  "${DG_BUILD}/ggml/src/ggml-base.lib")
