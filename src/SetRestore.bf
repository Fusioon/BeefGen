using System;

namespace BeefGen;

struct SetRestore<T> : IDisposable
{
	T* ptr;
	T val;

	public this(ref T valueRef, T value)
	{
		this.val = valueRef;
		this.ptr = &valueRef;

		valueRef = value;
	}

	public void Dispose()
	{
		*this.ptr = val;
	}
}