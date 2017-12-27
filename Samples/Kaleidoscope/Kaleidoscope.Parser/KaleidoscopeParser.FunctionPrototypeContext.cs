﻿// <copyright file="Parser.cs" company=".NET Foundation">
// Copyright (c) .NET Foundation. All rights reserved.
// </copyright>

using System.Collections.Generic;
using System.Linq;

namespace Kaleidoscope.Grammar
{
    public partial class KaleidoscopeParser
    {
        public partial class FunctionPrototypeContext
        {
            public override string Name => Identifier( 0 ).GetText();

            public override IReadOnlyList<(string Name, SourceSpan Span)> Parameters
                => Identifier( ).Skip( 1 ).Select( i => (i.GetText(), i.GetSourceSpan( )) ).ToList( );
        }
    }
}
