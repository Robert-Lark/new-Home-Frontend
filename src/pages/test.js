import React from 'react';
import {graphql} from "gatsby";


function test({data}) {
    console.log(data.content)
    return (
        <div>
            test
        </div>
    );
}

export default test;

// export const query = graphql`
//  query MyQuery {
//     content: allSanityInterview {
//       nodes {
//         answer1
//         answer10
//         answer11
//         answer12
//         answer13
//         answer14
//         answer16
//         answer15
//         answer17
//         answer18
//         answer19
//         answer2
//         answer20
//         answer3
//         answer4
//         answer5
//         answer6
//         answer7
//         answer8
//         answer9
//         cat
//         description
//         question1
//         question10
//         question11
//         question12
//         question13
//         question14
//         question15
//         question16
//         question17
//         question18
//         question19
//         question2
//         question20
//         question3
//         question4
//         question5
//         question6
//         question7
//         question8
//         question9
//         style1
//         style10
//         style11
//         style12
//         style13
//         style14
//         style15
//         style16
//         style17
//         style18
//         style19
//         style2
//         style20
//         style3
//         style4
//         style5
//         style6
//         style7
//         style8
//         style9
//         url
//         image {
//           asset {
//             fixed(width: 200, height: 200) {
//               ...GatsbySanityImageFixed
//             }
//             fluid(maxWidth: 200) {
//               ...GatsbySanityImageFluid
//             }
//           }
//         }
//         name
//       }
//     }
//   }`