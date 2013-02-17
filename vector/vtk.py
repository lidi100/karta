""" VTK file driver based on documentation from
http://vtk.org/VTK/img/file-formats.pdf """

import sys
import operator
from xml.etree import ElementTree as ET
from xml.dom import minidom
from geo_tools.vector.guppy import *

def mp2uvtk(mp_list, fnm, **kwargs):
    """ Write a list of Multipoint instances to a serial VTK PolyData (VTP)
    file.

    kwargs are:

        *vbyteorder*        :   'LittleEndian' or 'BigEndian' to force a byte
                                order other than the native order

        *write_pointdata*   :   {bool}, default True, to write point attributes
    """

    vtype = 'PolyData'
    vbyteorder = kwargs.get('byte_order', 'undef')
    if vbyteorder == 'undef':
        if sys.byteorder == 'little':
            vbyteorder = 'LittleEndian'
        else:
            vbyteorder = 'BigEndian'
    assert vbyteorder in ('LittleEndian', 'BigEndian')
    write_pointdata = kwargs.get('write_pointdata', True)

    vversion = str(kwargs.get('version', 0.1))

    xdoc = ET.Element('VTKFile', attrib={'type':vtype,
                                         'version':vversion,
                                         'byte_order':vbyteorder})

    xugrid = ET.SubElement(xdoc, vtype)

    if isinstance(mp_list, Multipoint):
        mp_list = [mp_list]

    for mp in mp_list:

        xpiece = ET.Element('Piece', attrib={'NumberOfPoints':str(len(mp)),
                                             'NumberOfVerts':str(len(mp))})
        xugrid.append(xpiece)

        # Point coordinates
        xpts = ET.Element('Points')
        xdarray = ET.Element('DataArray',
                        attrib={'NumberOfComponents':'{0}'.format(mp.rank),
                                'type':'Float32',
                                'format':'ascii'})
        xdarray.text = reduce(lambda a,b: str(a)+' '+str(b),    # Concat points
                        map(lambda pt:                          # Form points
                            reduce(lambda a,b: str(a)+' '+str(b), pt),
                            mp))                                # Concat coords

        xpts.append(xdarray)
        xpiece.append(xpts)

        # Point data
        if False in (a is None for a in mp.data) and write_pointdata:
            if hasattr(mp.data, 'keys'):
                datakeys = mp.data.keys()
                datavals = mp.data.values()
            else:
                datakeys = ['point_data']
                datavals = [mp.data]

            xptdata = ET.Element('PointData')
            for key, vals in zip(datakeys, datavals):
                if isinstance(vals[0], int):
                    dtype = 'Int32'
                elif isinstance(vals[0], float):
                    dtype = 'Float32'
                else:
                    dtype = 'String'
                xdarray = ET.Element('DataArray', attrib={'type':dtype,
                                                          'format':'ascii',
                                                          'Name':str(key)})
                xdarray.text = reduce(lambda a,b: str(a)+' '+str(b), vals)
                xptdata.append(xdarray)

            xpiece.append(xptdata)

        # Cell data
        xcell = ET.Element('Verts')
        connectivity = ET.Element('DataArray', attrib={'type':'Int32',
                                                       'Name':'connectivity',
                                                       'format':'ascii'})
        connectivity.text = reduce(operator.add,
                                [str(a)+' ' for a in range(len(mp))])

        offsets = ET.Element('DataArray', attrib={'type':'Int32',
                                                  'Name':'offsets',
                                                  'format':'ascii'})
        #offsets.text = str(len(mp))
        offsets.text = reduce(operator.add,
                                [str(a+1)+' ' for a in range(len(mp))])


        xcell.append(connectivity)
        xcell.append(offsets)
        xpiece.append(xcell)

    pretty_xml = minidom.parseString(ET.tostring(xdoc)).toprettyxml()

    with open(fnm, 'w') as f:
        f.write(pretty_xml)
    return

