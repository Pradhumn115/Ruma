from collections.abc import Sequence


from mlx.core import array, Dtype, Device, Stream
from typing import Sequence, Optional, Union

def layer_norm(x: array, weight: Optional[array], bias: Optional[array], eps: float, *, stream: Union[None, Stream, Device] = None) -> array:
    """
    Layer normalization.

    The normalization is with respect to the last axis of the input ``x``.

    Args:
        x (array): Input array.
        weight (array, optional): A multiplicative weight to scale the result by.
          The ``weight`` should be one-dimensional with the same size
          as the last axis of ``x``. If set to ``None`` then no scaling happens.
        bias (array, optional): An additive offset to be added to the result.
          The ``bias`` should be one-dimensional with the same size
          as the last axis of ``x``. If set to ``None`` then no translation happens.
        eps (float): A small additive constant for numerical stability.

    Returns:
        array: The output array.
    """

def metal_kernel(name: str, input_names: Sequence[str], output_names: Sequence[str], source: str, header: str = '', ensure_row_contiguous: bool = True, atomic_outputs: bool = False) -> object:
    r"""
    A jit-compiled custom Metal kernel defined from a source string.

    Full documentation: :ref:`custom_metal_kernels`.

    Args:
      name (str): Name for the kernel.
      input_names (List[str]): The parameter names of the inputs in the
         function signature.
      output_names (List[str]): The parameter names of the outputs in the
         function signature.
      source (str): Source code. This is the body of a function in Metal,
         the function signature will be automatically generated.
      header (str): Header source code to include before the main function.
         Useful for helper functions or includes that should live outside of
         the main function body.
      ensure_row_contiguous (bool): Whether to ensure the inputs are row contiguous
         before the kernel runs. Default: ``True``.
      atomic_outputs (bool): Whether to use atomic outputs in the function signature
         e.g. ``device atomic<float>``. Default: ``False``.

    Returns:
      Callable ``metal_kernel``.

    Example:

      .. code-block:: python

        def exp_elementwise(a: mx.array):
            source = \'\''
                uint elem = thread_position_in_grid.x;
                T tmp = inp[elem];
                out[elem] = metal::exp(tmp);
            \'\''

            kernel = mx.fast.metal_kernel(
                name="myexp",
                input_names=["inp"],
                output_names=["out"],
                source=source
            )
            outputs = kernel(
                inputs=[a],
                template=[("T", mx.float32)],
                grid=(a.size, 1, 1),
                threadgroup=(256, 1, 1),
                output_shapes=[a.shape],
                output_dtypes=[a.dtype],
                verbose=True,
            )
            return outputs[0]

        a = mx.random.normal(shape=(4, 16)).astype(mx.float16)
        b = exp_elementwise(a)
        assert mx.allclose(b, mx.exp(a))
    """

def rms_norm(x: array, weight: Optional[array], eps: float, *, stream: Union[None, Stream, Device] = None) -> array:
    """
    Root Mean Square normalization (RMS norm).

    The normalization is with respect to the last axis of the input ``x``.

    Args:
        x (array): Input array.
        weight (array, optional): A multiplicative weight to scale the result by.
          The ``weight`` should be one-dimensional with the same size
          as the last axis of ``x``. If set to ``None`` then no scaling happens.
        eps (float): A small additive constant for numerical stability.

    Returns:
        array: The output array.
    """

def rope(a: array, dims: int, *, traditional: bool, base: Optional[float], scale: float, offset: Union[int, array], freqs: Optional[array] = None, stream: Union[None, Stream, Device] = None) -> array:
    """
    Apply rotary positional encoding to the input.

    Args:
        a (array): Input array.
        dims (int): The feature dimensions to be rotated. If the input feature
          is larger than dims then the rest is left unchanged.
        traditional (bool): If set to ``True`` choose the traditional
          implementation which rotates consecutive dimensions.
        base (float, optional): The base used to compute angular frequency for
          each dimension in the positional encodings. Exactly one of ``base`` and
          ``freqs`` must be ``None``.
        scale (float): The scale used to scale the positions.
        offset (int or array): The position offset to start at.
        freqs (array, optional): Optional frequencies to use with RoPE.
          If set, the ``base`` parameter must be ``None``. Default: ``None``.

    Returns:
        array: The output array.
    """

def scaled_dot_product_attention(q: array, k: array, v: array, *, scale: float,  mask: Union[None, str, array] = None, stream: Union[None, Stream, Device] = None) -> array:
    """
    A fast implementation of multi-head attention: ``O = softmax(Q @ K.T, dim=-1) @ V``.

    Supports:

    * `Multi-Head Attention <https://arxiv.org/abs/1706.03762>`_
    * `Grouped Query Attention <https://arxiv.org/abs/2305.13245>`_
    * `Multi-Query Attention <https://arxiv.org/abs/1911.02150>`_

    Note: The softmax operation is performed in ``float32`` regardless of
    the input precision.

    Note: For Grouped Query Attention and Multi-Query Attention, the ``k``
    and ``v`` inputs should not be pre-tiled to match ``q``.

    In the following the dimensions are given by:

    * ``B``: The batch size.
    * ``N_q``: The number of query heads.
    * ``N_kv``: The number of key and value heads.
    * ``T_q``: The number of queries per example.
    * ``T_kv``: The number of keys and values per example.
    * ``D``: The per-head dimension.

    Args:
        q (array): Queries with shape ``[B, N_q, T_q, D]``.
        k (array): Keys with shape ``[B, N_kv, T_kv, D]``.
        v (array): Values with shape ``[B, N_kv, T_kv, D]``.
        scale (float): Scale for queries (typically ``1.0 / sqrt(q.shape(-1)``)
        mask (Union[None, str, array], optional): A causal, boolean or additive
           mask to apply to the query-key scores. The mask can have at most 4
           dimensions and must be broadcast-compatible with the shape
           ``[B, N, T_q, T_kv]``. If an additive mask is given its type must
           promote to the promoted type of ``q``, ``k``, and ``v``.
    Returns:
        array: The output array.
    """
