﻿// <copyright file="ReplLoop.cs" company=".NET Foundation">
// Copyright (c) .NET Foundation. All rights reserved.
// </copyright>

using System;

namespace Kaleidoscope.Runtime
{
    public class ReadyStateChangedArgs
        : EventArgs
    {
        public ReadyStateChangedArgs( bool partialParse )
        {
            PartialParse = partialParse;
        }

        public bool PartialParse { get; }

        public static ReadyStateChangedArgs PartialParseArgs { get; } = new ReadyStateChangedArgs( true );

        public static ReadyStateChangedArgs CompleteParseArgs { get; } = new ReadyStateChangedArgs( false );
    }
}
