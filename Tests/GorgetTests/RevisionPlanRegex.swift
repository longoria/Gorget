import Foundation
import RegexBuilder

let revisionPlanRegex = Regex {
    """
Gorget Revise Content Plan:


:::::::::::::::::::::::::::::::::::::::::::::::::::::

"""
    OneOrMore(.any)
    "Creating destination directory:"
    OneOrMore(.any)
    "Gorget_Revised"
    OneOrMore(.any)
"""
:::::::::::::::::::::::::::::::::::::::::::::::::::::

Opaque Files:
Copying:
"""
    OneOrMore(.any)
    "[(src:"
    OneOrMore(.any)
    "Input/4.jpg"
    OneOrMore(.any)
    "file:///"
    OneOrMore(.any)
    ", dest: file:///"
    OneOrMore(.any)
    "/Gorget_Revised/4.jpg), (src: "
    OneOrMore(.any)
    "Input/5.png"
    OneOrMore(.any)
    "file:///"
    OneOrMore(.any)
    ", dest: file:///"
    OneOrMore(.any)
    "/Gorget_Revised/5.png)]"
    OneOrMore(.any)
"""
Finding/Replacing:
In above copy set:
[]


:::::::::::::::::::::::::::::::::::::::::::::::::::::

Note: A last pass for files modified due to name revision changes in it's content may reflect outside above set

:::::::::::::::::::::::::::::::::::::::::::::::::::::

Text Files:
Copying:
"""
    OneOrMore(.any)
    "[(src: "
    Optionally("Contents/")
    "Resources/Resources/Input/1.txt -- file:///"
    OneOrMore(.any)
    ", dest: file:///"
    OneOrMore(.any)
    "/Gorget_Revised/1.txt)]"
    OneOrMore(.any)
"""
Finding/Replacing:
In above copy set:
[]


:::::::::::::::::::::::::::::::::::::::::::::::::::::

Note: A last pass for files modified due to name revision changes in it's content may reflect outside above set

:::::::::::::::::::::::::::::::::::::::::::::::::::::

Manifest Files:
Copying:
"""
    OneOrMore(.any)
    "[(src:"
    OneOrMore(.any)
    "/Input/2.html -- file:///"
    OneOrMore(.any)
    ", dest: file:///"
    OneOrMore(.any)
    "/Gorget_Revised/2.html), (src:"
    OneOrMore(.any)
    "/Input/3.rss -- file:///"
    OneOrMore(.any)
    ", dest: file:///"
    OneOrMore(.any)
    "/Gorget_Revised/3.rss)]"
    OneOrMore(.any)
"""
Finding/Replacing:
In above copy set:
[]


:::::::::::::::::::::::::::::::::::::::::::::::::::::

Note: A last pass for files modified due to name revision changes in it's content may reflect outside above set
"""
    ZeroOrMore(.any)
}
