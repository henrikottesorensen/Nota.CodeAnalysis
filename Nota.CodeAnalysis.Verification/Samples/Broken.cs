using Nota.Vendor;
using System;
using System.Xml;

namespace Nota.Verification;

/// <summary>Deliberately wrong. Every diagnostic here is asserted by verify.sh.</summary>
public static class Broken
{
    /// <summary>Uses var, which IDE0008 forbids.</summary>
    public static string Value()
    {
        var text = typeof(Thing).Name + Environment.NewLine;

        return text;
    }
}
