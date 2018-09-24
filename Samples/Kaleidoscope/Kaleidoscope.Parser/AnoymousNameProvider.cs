﻿// <copyright file="AnoymousNameProvider.cs" company=".NET Foundation">
// Copyright (c) .NET Foundation. All rights reserved.
// </copyright>

using System.Collections;
using System.Collections.Generic;

namespace Kaleidoscope.Grammar
{
    /// <summary>Provides anonymous names as a sequence of strings</summary>
    /// <remarks>Each call to <see cref="GetEnumerator"/> starts a new sequence</remarks>
    public class AnoymousNameProvider
        : IEnumerable<string>
    {
        /// <summary>Initializes a new instance of the <see cref="AnoymousNameProvider"/> class.</summary>
        /// <param name="prefix">Prefix to use for the name</param>
        public AnoymousNameProvider(string prefix)
        {
            NamePrefix = prefix;
        }

        public IEnumerator<string> GetEnumerator( )
        {
            int anonymousIndex = 0;
            while( true )
            {
                yield return $"{NamePrefix}{anonymousIndex++}";
            }
        }

        IEnumerator IEnumerable.GetEnumerator( )
        {
            return GetEnumerator( );
        }

        private readonly string NamePrefix;
    }
}
